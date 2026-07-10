import Foundation
import HealthKit

/// W1: Watch/iPhone sensors → Apple Health → samples for Core `health.ingest`.
/// Pull-on-open only (no background observer in v1).
@MainActor
public final class HealthKitBridge: ObservableObject {
    public static let shared = HealthKitBridge()

    @Published public var lastError: String?
    @Published public var lastSyncSummary: String = ""
    @Published public var authorizationRequested: Bool = UserDefaults.standard.bool(forKey: "hk.authRequested")

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

    public func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "이 기기에서는 Apple 건강을 쓸 수 없어요."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorizationRequested = true
            UserDefaults.standard.set(true, forKey: "hk.authRequested")
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

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

        // Aggregate asleep seconds per calendar day (device TZ).
        var byDay: [String: TimeInterval] = [:]
        let cal = Calendar.current
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"

        for s in samples {
            // Asleep values (in bed alone is weaker signal — still count asleep*).
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
            // Anchor ts at noon local so dayKey matches.
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
}
