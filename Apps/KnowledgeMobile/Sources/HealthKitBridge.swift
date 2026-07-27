import Foundation
import HealthKit
import UIKit

/// W1: Watch/iPhone sensors → Apple Health → samples for Core `health.ingest`.
/// Pull-on-open only (no background observer in v1).
///
/// Permission honesty (Apple policy):
/// - Read 권한 거부 여부는 API로 확정할 수 없음 (빈 결과 = 거부 또는 데이터 없음).
/// - 앱은 **요청 필요 여부**(`getRequestStatusForAuthorization`)와
///   **동기 결과**로 상태를 추정하고, 설정·건강 앱으로 바로 가는 안내를 제공해야 함.
@MainActor
public final class HealthKitBridge: ObservableObject {
    public static let shared = HealthKitBridge()

    public enum PermissionPhase: String, Equatable {
        /// 시뮬레이터 등 Health 불가
        case unavailable
        /// 아직 시스템 권한 시트 미요청
        case shouldRequest
        /// 요청 이력 있음 — 읽기 허용/거부는 설정에서만 변경
        case requested
        /// 상태 조회 실패
        case error
    }

    @Published public var lastError: String?
    @Published public var lastSyncSummary: String = ""
    @Published public var authorizationRequested: Bool = UserDefaults.standard.bool(forKey: "hk.authRequested")
    /// 최근 동기에서 샘플을 읽었거나(수락/중복) 반영한 적 있음 — 홈 배너 숨김용
    @Published public var lastIngestHadSamples: Bool = UserDefaults.standard.bool(forKey: "hk.lastIngestHadSamples")
    @Published public var phase: PermissionPhase = .unavailable
    /// 한 줄 상태 (UI 배지)
    @Published public var statusTitle: String = "확인 중…"
    /// 사용자 안내 본문
    @Published public var statusDetail: String = ""
    /// 번호 단계 가이드
    @Published public var guideSteps: [String] = []
    /// 홈/설정에서 CTA 노출
    @Published public var needsUserAction: Bool = false
    /// 타입별 요청 대상 라벨 (운동/수면/체중)
    @Published public var typeLabels: [String] = ["운동", "수면", "체중"]

    private let store = HKHealthStore()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        ]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            set.insert(sleep)
        }
        return set
    }

    // MARK: - Permission status

    /// 앱이 권한 상태를 스스로 갱신. 화면 진입·동기 전 호출.
    public func refreshPermissionState() async {
        lastError = nil
        guard isAvailable else {
            phase = .unavailable
            statusTitle = "이 기기에서 사용 불가"
            statusDetail = "Apple 건강을 지원하지 않는 기기예요. (시뮬레이터 등)"
            guideSteps = []
            needsUserAction = false
            return
        }

        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            switch status {
            case .shouldRequest:
                phase = .shouldRequest
                authorizationRequested = false
                statusTitle = "권한 허용 필요"
                statusDetail = "워치·아이폰 운동·수면·체중을 읽으려면 Apple 건강 권한이 필요해요. 쓰기는 하지 않아요."
                guideSteps = Self.guideStepsShouldRequest
                needsUserAction = true
            case .unnecessary:
                phase = .requested
                authorizationRequested = true
                UserDefaults.standard.set(true, forKey: "hk.authRequested")
                if lastIngestHadSamples {
                    statusTitle = "연결됨"
                    statusDetail = lastSyncSummary.isEmpty
                        ? "권한 요청 완료. 앱을 열 때 최근 7일 운동·수면·체중을 Mac으로 가져와요."
                        : lastSyncSummary
                    guideSteps = Self.guideStepsOpenSettings
                    needsUserAction = false
                } else {
                    statusTitle = "권한 요청 완료 · 데이터 미확인"
                    statusDetail = "시스템 권한 화면은 이미 처리됐어요. 샘플이 비면 설정에서 읽기를 켜 주세요. (거부 여부는 iOS 정책상 앱이 확정할 수 없어요.)"
                    guideSteps = Self.guideStepsOpenSettings
                    needsUserAction = true
                }
            case .unknown:
                fallthrough
            @unknown default:
                phase = .error
                statusTitle = "권한 상태 불명"
                statusDetail = "상태를 확인하지 못했어요. 아래에서 권한을 다시 요청하거나 설정으로 이동해 주세요."
                guideSteps = Self.guideStepsOpenSettings
                needsUserAction = true
            }
        } catch {
            phase = .error
            lastError = error.localizedDescription
            statusTitle = "권한 확인 실패"
            statusDetail = error.localizedDescription
            guideSteps = Self.guideStepsOpenSettings
            needsUserAction = true
        }
    }

    public static let guideStepsShouldRequest: [String] = [
        "아래 「권한 허용하기」를 눌러 시스템 창에서 운동·수면·체중을 허용해요.",
        "나중에 막혔다면: 설정 → 건강 → 데이터 접근 및 기기 → Knowledge",
        "또는 설정 → Knowledge → 건강 에서 읽기를 켤 수 있어요.",
    ]

    public static let guideStepsOpenSettings: [String] = [
        "설정 → 건강 → 데이터 접근 및 기기 → Knowledge",
        "운동 · 수면 분석 · 체중 읽기를 모두 켜요.",
        "또는 설정 → Knowledge 앱 → 건강 메뉴를 확인해요.",
        "워치 데이터가 건강 앱에 보이는지도 확인해요.",
    ]

    public func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "이 기기에서는 Apple 건강을 쓸 수 없어요."
            await refreshPermissionState()
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorizationRequested = true
            UserDefaults.standard.set(true, forKey: "hk.authRequested")
            lastError = nil
            await refreshPermissionState()
            return true
        } catch {
            lastError = error.localizedDescription
            statusTitle = "권한 요청 실패"
            statusDetail = error.localizedDescription
            needsUserAction = true
            return false
        }
    }

    // MARK: - Deep links / settings

    /// 이 앱의 iOS 설정 화면 (건강 토글이 보일 수 있음).
    public func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Apple 건강 앱 (데이터 확인용).
    public func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else {
            openAppSettings()
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            if !ok {
                Task { @MainActor in self?.openAppSettings() }
            }
        }
    }

    // MARK: - Collect samples

    /// Collect last `days` of workouts, sleep, latest body mass.
    public func collectSamples(days: Int = 7) async throws -> [[String: Any]] {
        guard isAvailable else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end.addingTimeInterval(-86400 * Double(days))
        var samples: [[String: Any]] = []
        samples.append(contentsOf: try await fetchWorkouts(from: start, to: end))
        samples.append(contentsOf: try await fetchSleep(from: start, to: end))
        if let weight = try await fetchLatestWeight(from: start, to: end) {
            samples.append(weight)
        }
        return samples
    }

    private func fetchWorkouts(from start: Date, to end: Date) async throws -> [[String: Any]] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return workouts.compactMap { w in
            let minutes = max(1, Int((w.duration / 60.0).rounded()))
            let kind = workoutKind(w.workoutActivityType)
            return [
                "client_id": "hk-workout-\(w.uuid.uuidString)",
                "type": "workout",
                "ts": iso.string(from: w.startDate),
                "kind": kind,
                "minutes": minutes,
                "source": "healthkit",
            ]
        }
    }

    private func fetchSleep(from start: Date, to end: Date) async throws -> [[String: Any]] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        var byDay: [String: TimeInterval] = [:]
        let cal = Calendar.current
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"

        for s in samples {
            let v = s.value
            let isAsleep: Bool
            if #available(iOS 16.0, *) {
                isAsleep = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ].contains(v)
            } else {
                isAsleep = v == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
            guard isAsleep else { continue }
            let key = dayFmt.string(from: cal.startOfDay(for: s.startDate))
            byDay[key, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }

        return byDay.compactMap { day, seconds -> [String: Any]? in
            let hours = seconds / 3600.0
            guard hours >= 0.5 else { return nil }
            guard let noon = dayFmt.date(from: day)?.addingTimeInterval(12 * 3600) else { return nil }
            return [
                "client_id": "hk-sleep-\(day)",
                "type": "metric",
                "ts": iso.string(from: noon),
                "sleep_h": (hours * 10).rounded() / 10,
                "source": "healthkit",
            ]
        }
    }

    private func fetchLatestWeight(from start: Date, to end: Date) async throws -> [String: Any]? {
        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: massType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        guard let s = samples.first else { return nil }
        let kg = s.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        return [
            "client_id": "hk-weight-\(s.uuid.uuidString)",
            "type": "metric",
            "ts": iso.string(from: s.startDate),
            "weight_kg": (kg * 10).rounded() / 10,
            "source": "healthkit",
        ]
    }

    private func workoutKind(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .walking: return "걷기"
        case .running: return "달리기"
        case .cycling: return "자전거"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "근력"
        case .yoga: return "요가"
        case .swimming: return "수영"
        case .hiking: return "등산"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "운동"
        }
    }

    /// 동기 후 빈 결과일 때 상태 문구 보강.
    public func markEmptySyncOutcome() {
        lastIngestHadSamples = false
        UserDefaults.standard.set(false, forKey: "hk.lastIngestHadSamples")
        statusTitle = "데이터 없음 또는 읽기 거부"
        statusDetail = "최근 7일 건강 샘플이 비어 있어요. 권한이 꺼져 있거나, 워치 기록이 건강 앱에 없을 수 있어요. 아래 「설정 앱에서 허용하기」로 바로 이동할 수 있어요."
        guideSteps = Self.guideStepsOpenSettings
        needsUserAction = true
        lastSyncSummary = statusDetail
    }

    public func markSuccessfulSync(accepted: Int, deduped: Int) {
        lastSyncSummary = "건강 동기 \(accepted)건 반영 · 중복 \(deduped)"
        if accepted > 0 || deduped > 0 {
            lastIngestHadSamples = true
            UserDefaults.standard.set(true, forKey: "hk.lastIngestHadSamples")
            statusTitle = "동기화됨"
            statusDetail = lastSyncSummary
            needsUserAction = false
        } else {
            markEmptySyncOutcome()
        }
    }
}
