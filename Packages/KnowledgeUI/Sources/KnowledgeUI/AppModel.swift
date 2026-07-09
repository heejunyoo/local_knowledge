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
    private var didBootstrap = false

    public struct MeetingRow: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var status: String
        public var errorCode: String?
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

    /// Caption under status (never tells user to run CLI).
    public var connectionCaption: String {
        if isStartingBackend { return "잠시만요, 준비하고 있어요" }
        if healthOK { return "모든 준비가 끝났어요" }
        if lastError != nil { return "다시 시도하는 중이에요" }
        return "연결을 확인하는 중이에요"
    }

    public func startPolling() {
        bootstrapBackendIfNeeded()
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.bootstrapBackendIfNeeded()
                self?.refresh()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Auto-start knowledged — user never touches CLI.
    public func bootstrapBackendIfNeeded() {
        if healthOK { return }
        if isStartingBackend { return }

        // Fast path: already healthy
        if supervisor.probeHealth() != nil {
            applyHealthOK(version: supervisor.probeHealth() ?? "")
            return
        }

        isStartingBackend = true
        statusMessage = "준비하고 있어요"
        lastError = nil

        // Run ensure off main-ish wait on cooperative: short block OK for local spawn
        let result = supervisor.ensureReady(timeout: 10)
        isStartingBackend = false

        switch result {
        case let .ready(version):
            applyHealthOK(version: version)
            didBootstrap = true
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
        if !isRecording {
            statusMessage = "녹음할 준비가 됐어요"
        }
        lastError = nil
    }

    public func refresh() {
        // If down, try silent restart (throttled inside supervisor)
        if supervisor.probeHealth() == nil {
            healthOK = false
            if !isStartingBackend {
                bootstrapBackendIfNeeded()
            }
            if !healthOK && !isStartingBackend {
                statusMessage = isRecording ? statusMessage : "연결을 복구하는 중이에요"
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
                    let title = item["title"]?.stringValue ?? "제목 없는 미팅"
                    let status = item["status"]?.stringValue ?? "?"
                    let err = item["error_code"]?.stringValue
                    return MeetingRow(id: id, title: title, status: status, errorCode: err)
                }
            }
            lastError = nil
            if !isRecording {
                if reviewCount > 0 {
                    statusMessage = "확인이 필요해요"
                } else if failedCount > 0 {
                    statusMessage = "문제가 생겼어요. 다시 시도해 주세요"
                } else {
                    statusMessage = "녹음할 준비가 됐어요"
                }
            }
        } catch {
            healthOK = false
            // Never: "데몬을 켜 주세요"
            if !isStartingBackend {
                bootstrapBackendIfNeeded()
            }
        }
    }

    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
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
            _ = try capture.stopSession()
            isRecording = false
            activeMeetingId = nil
            self.capture = nil
            statusMessage = "정리하는 중…"
            refresh()
        } catch {
            lastError = String(describing: error)
            statusMessage = "녹음 저장에 실패했어요"
            isRecording = false
        }
    }

    private func defaultTitle() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm 미팅"
        return f.string(from: Date())
    }
}
