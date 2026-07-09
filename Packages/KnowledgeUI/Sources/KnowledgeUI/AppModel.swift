import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC
import KnowledgeCapture
import Combine

@MainActor
public final class AppModel: ObservableObject {
    public let knowledgeRoot: URL
    public let socketPath: String

    @Published public var healthOK: Bool = false
    @Published public var isStartingBackend: Bool = false
    @Published public var isProcessing: Bool = false
    @Published public var daemonVersion: String = ""
    @Published public var recordingCount: Int = 0
    @Published public var reviewCount: Int = 0
    @Published public var meetings: [MeetingRow] = []
    @Published public var isRecording: Bool = false
    @Published public var activeMeetingId: String?
    @Published public var statusMessage: String = "준비하고 있어요"
    @Published public var lastError: String?

    private var capture: CaptureSessionController?
    private var pollTimer: Timer?
    private let supervisor: DaemonSupervisor
    private var asrInFlight = Set<String>()

    public struct MeetingRow: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var status: String
        public var errorCode: String?
        public var audioPath: String?
    }

    public init(knowledgeRoot: URL = KnowledgePaths.defaultKnowledgeRoot) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
        self.supervisor = DaemonSupervisor(knowledgeRoot: knowledgeRoot)
        try? KnowledgePaths.ensureLayout(at: knowledgeRoot)
    }

    public var failedCount: Int {
        meetings.filter { $0.status.contains("fail") }.count
    }

    public var connectionCaption: String {
        if isStartingBackend { return "잠시만요, 준비하고 있어요" }
        if isProcessing { return "방금 녹음을 정리하고 있어요" }
        if healthOK { return "모든 준비가 끝났어요" }
        if lastError != nil { return "다시 시도하는 중이에요" }
        return "연결을 확인하는 중이에요"
    }

    public func startPolling() {
        bootstrapBackendIfNeeded()
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.bootstrapBackendIfNeeded()
                self?.refresh()
                self?.kickPendingASR()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func bootstrapBackendIfNeeded() {
        if healthOK { return }
        if isStartingBackend { return }

        if let v = supervisor.probeHealth() {
            applyHealthOK(version: v)
            return
        }

        isStartingBackend = true
        statusMessage = "준비하고 있어요"
        lastError = nil

        let result = supervisor.ensureReady(timeout: 10)
        isStartingBackend = false

        switch result {
        case let .ready(version):
            applyHealthOK(version: version)
        case .starting:
            statusMessage = "준비하고 있어요"
        case let .failed(message):
            healthOK = false
            statusMessage = "잠시 후 다시 시도해 주세요"
            lastError = message
        }
    }

    private func applyHealthOK(version: String) {
        healthOK = true
        daemonVersion = version
        if !isRecording && !isProcessing {
            statusMessage = "녹음할 준비가 됐어요"
        }
        lastError = nil
    }

    public func refresh() {
        if supervisor.probeHealth() == nil {
            healthOK = false
            if !isStartingBackend {
                bootstrapBackendIfNeeded()
            }
            if !healthOK && !isStartingBackend && !isRecording {
                statusMessage = "연결을 복구하는 중이에요"
            }
            return
        }

        do {
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }

            let health = try client.call(JSONRPCRequest(method: "health"))
            if let err = health.error {
                healthOK = false
                lastError = err.message
                return
            }
            healthOK = true
            if case let .string(v) = health.result?["version"] { daemonVersion = v }
            if case let .number(n) = health.result?["recording_count"] { recordingCount = Int(n) }
            if case let .number(n) = health.result?["review_needed_count"] { reviewCount = Int(n) }

            let list = try client.call(JSONRPCRequest(method: "meeting.list"))
            if case let .array(arr) = list.result {
                meetings = arr.compactMap { item in
                    guard let id = item["id"]?.stringValue else { return nil }
                    return MeetingRow(
                        id: id,
                        title: item["title"]?.stringValue ?? "제목 없는 미팅",
                        status: item["status"]?.stringValue ?? "?",
                        errorCode: item["error_code"]?.stringValue,
                        audioPath: item["audio_path"]?.stringValue
                    )
                }
            }

            if !isRecording && !isProcessing {
                if reviewCount > 0 {
                    statusMessage = "확인이 필요해요"
                } else if failedCount > 0 {
                    statusMessage = "문제가 생겼어요. 다시 시도해 주세요"
                } else {
                    statusMessage = "녹음할 준비가 됐어요"
                }
                lastError = nil
            }
        } catch {
            healthOK = false
            if !isStartingBackend {
                bootstrapBackendIfNeeded()
            }
        }
    }

    /// Auto-pick meetings that need UI-side speech ASR.
    public func kickPendingASR() {
        guard healthOK, !isRecording else { return }
        for row in meetings {
            guard !asrInFlight.contains(row.id) else { continue }
            let needs =
                row.status == "recorded"
                || row.errorCode == "needs_ui_asr"
                || row.errorCode == "asr_tools_missing"
                || (row.status == "transcribe_failed" && row.audioPath != nil)
                || (row.status == "transcribing" && row.audioPath != nil)
            guard needs, let audio = row.audioPath else { continue }
            asrInFlight.insert(row.id)
            Task { @MainActor in
                await self.runLocalASR(meetingId: row.id, audioRel: audio)
                self.asrInFlight.remove(row.id)
            }
            break // one at a time
        }
    }

    public func startRecording() {
        lastError = nil
        if !healthOK {
            bootstrapBackendIfNeeded()
        }
        guard healthOK else {
            statusMessage = "아직 준비가 덜 됐어요. 잠깐만요"
            return
        }
        do {
            let ctrl = CaptureSessionController(knowledgeRoot: knowledgeRoot, socketPath: socketPath)
            let id = try ctrl.startSession(title: defaultTitle())
            capture = ctrl
            activeMeetingId = id
            isRecording = true
            statusMessage = "듣고 있어요"
            refresh()
        } catch {
            lastError = String(describing: error)
            statusMessage = "녹음을 시작하지 못했어요"
        }
    }

    public func stopRecording() {
        guard let capture else {
            isRecording = false
            return
        }
        do {
            let artifact = try capture.stopSession()
            let mid = activeMeetingId
            isRecording = false
            activeMeetingId = nil
            self.capture = nil
            isProcessing = true
            statusMessage = "받아쓰는 중…"
            refresh()
            if let mid {
                asrInFlight.insert(mid)
                Task { @MainActor in
                    await self.runLocalASR(meetingId: mid, audioRel: artifact.path)
                    self.asrInFlight.remove(mid)
                }
            }
        } catch {
            lastError = String(describing: error)
            statusMessage = "녹음 저장에 실패했어요"
            isRecording = false
            isProcessing = false
        }
    }

    public func runLocalASR(meetingId: String, audioRel: String?) async {
        isProcessing = true
        statusMessage = "받아쓰는 중…"
        lastError = nil
        do {
            var audioPath = audioRel
            if audioPath == nil {
                let client = UnixDomainClient(socketPath: socketPath)
                try client.connect()
                defer { client.close() }
                let get = try client.call(JSONRPCRequest(
                    method: RPCMethod.meetingGet.rawValue,
                    params: .object(["id": .string(meetingId)])
                ))
                audioPath = get.result?["audio_path"]?.stringValue
            }
            guard let audioPath else {
                statusMessage = "녹음 파일을 찾지 못했어요"
                isProcessing = false
                return
            }

            try await LocalASRService.transcribeAndComplete(
                knowledgeRoot: knowledgeRoot,
                socketPath: socketPath,
                meetingId: meetingId,
                audioRelPath: audioPath
            )
            statusMessage = "정리하는 중…"
            refresh()

            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                refresh()
                if let row = meetings.first(where: { $0.id == meetingId }) {
                    if row.status == "review_needed" {
                        statusMessage = "확인이 필요해요"
                        isProcessing = false
                        return
                    }
                    if row.status == "summary_failed" {
                        statusMessage = "요약에 실패했어요"
                        lastError = row.errorCode
                        isProcessing = false
                        return
                    }
                    if row.status == "committed" {
                        statusMessage = "저장했어요"
                        isProcessing = false
                        return
                    }
                }
            }
            isProcessing = false
            statusMessage = "정리하는 중… 잠시 후 목록을 확인해 주세요"
            refresh()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "받아쓰기에 실패했어요"
            isProcessing = false
            refresh()
        }
    }

    public func acceptReview(meetingId: String) {
        lastError = nil
        do {
            if !healthOK { bootstrapBackendIfNeeded() }
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }
            let res = try client.call(JSONRPCRequest(
                method: RPCMethod.meetingReviewAccept.rawValue,
                params: .object(["id": .string(meetingId)])
            ))
            if let err = res.error {
                lastError = err.message
                statusMessage = "저장하지 못했어요"
                return
            }
            statusMessage = "저장했어요"
            refresh()
        } catch {
            lastError = String(describing: error)
            statusMessage = "저장하지 못했어요"
        }
    }

    public func retryMeeting(meetingId: String) {
        Task { @MainActor in
            asrInFlight.insert(meetingId)
            defer { asrInFlight.remove(meetingId) }
            do {
                let client = UnixDomainClient(socketPath: socketPath)
                try client.connect()
                defer { client.close() }
                let get = try client.call(JSONRPCRequest(
                    method: RPCMethod.meetingGet.rawValue,
                    params: .object(["id": .string(meetingId)])
                ))
                let audio = get.result?["audio_path"]?.stringValue
                _ = try client.call(JSONRPCRequest(
                    method: RPCMethod.meetingRetry.rawValue,
                    params: .object(["id": .string(meetingId)])
                ))
                await runLocalASR(meetingId: meetingId, audioRel: audio)
            } catch {
                lastError = String(describing: error)
            }
        }
    }

    private func defaultTitle() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm 미팅"
        return f.string(from: Date())
    }
}
