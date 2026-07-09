import Foundation
import AppKit
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
    private var isStartingCapture = false
    private let dbPath: String

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
        self.dbPath = knowledgeRoot.appendingPathComponent("index/knowledge.db").path
        self.supervisor = DaemonSupervisor(knowledgeRoot: knowledgeRoot)
        try? KnowledgePaths.ensureLayout(at: knowledgeRoot)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.appendUILog("AppModel bootstrap task")
            self.startPolling()
        }
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
        kickPendingASR()
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
            if !isStartingBackend { bootstrapBackendIfNeeded() }
            return
        }
        healthOK = true

        // Local DB is SoT for list (avoids JSONValue array decode issues on RPC).
        do {
            let store = try KnowledgeStore(path: dbPath)
            let rows = try PipelineStatus.allCases.flatMap { try store.meetings(withStatus: $0) }
            meetings = rows.map { m in
                MeetingRow(
                    id: m.id,
                    title: m.title ?? "제목 없는 미팅",
                    status: m.status.rawValue,
                    errorCode: m.errorCode,
                    audioPath: m.audioPath
                )
            }
            reviewCount = rows.filter { $0.status == .reviewNeeded }.count
            recordingCount = rows.filter { $0.status == .recording }.count
            appendUILog("refresh meetings=\(meetings.count) withAudio=\(meetings.filter { $0.audioPath != nil }.count)")
        } catch {
            appendUILog("refresh db error \(error)")
            lastError = String(describing: error)
        }

        if !isRecording && !isProcessing {
            if reviewCount > 0 {
                statusMessage = "확인이 필요해요"
            } else if failedCount > 0 {
                statusMessage = "문제가 생겼어요. 다시 시도해 주세요"
            } else if meetings.contains(where: { $0.status == "recorded" && $0.audioPath != nil }) {
                statusMessage = "받아쓰는 중…"
            } else {
                statusMessage = "녹음할 준비가 됐어요"
            }
        }
    }

    public func kickPendingASR() {
        guard healthOK else {
            appendUILog("kick skip healthOK=false")
            return
        }
        let liveId = isRecording ? activeMeetingId : nil
        for row in meetings {
            if row.id == liveId { continue }
            guard !asrInFlight.contains(row.id) else { continue }
            let needs =
                row.status == "recorded"
                || row.errorCode == "needs_ui_asr"
                || row.errorCode == "asr_tools_missing"
                || (row.status == "transcribe_failed" && row.audioPath != nil)
                || (row.status == "transcribing" && row.audioPath != nil)
            guard needs, let audio = row.audioPath else { continue }
            asrInFlight.insert(row.id)
            appendUILog("kick START \(row.id) \(row.status) \(audio)")
            Task { @MainActor in
                await self.runLocalASR(meetingId: row.id, audioRel: audio)
                self.asrInFlight.remove(row.id)
            }
            break
        }
    }

    public func startRecording() {
        lastError = nil
        if isStartingCapture || isRecording {
            statusMessage = "이미 녹음을 준비하고 있어요"
            return
        }
        if !healthOK { bootstrapBackendIfNeeded() }
        guard healthOK else {
            statusMessage = "아직 준비가 덜 됐어요. 잠깐만요"
            return
        }
        isStartingCapture = true
        Task { @MainActor in
            defer { isStartingCapture = false }
            do {
                // Cancel any in-memory capture left over
                if let old = capture {
                    try? old.failSession()
                    capture = nil
                    isRecording = false
                    activeMeetingId = nil
                }
                // Clear leftover recording rows from crashes before create
                try? abandonOrphanRecordings()
                // Also force-clear via local DB (belt and suspenders)
                try? forceAbandonRecordingRowsLocally()

                let ctrl = CaptureSessionController(
                    knowledgeRoot: knowledgeRoot,
                    socketPath: socketPath,
                    mode: .systemAudio
                )
                statusMessage = "시스템 오디오 연결 중…"
                let id = try await ctrl.startSession(title: defaultTitle())
                capture = ctrl
                activeMeetingId = id
                isRecording = true
                statusMessage = "회의 소리를 듣고 있어요"
                appendUILog("system audio recording started \(id)")
                refresh()
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription
                    ?? (error as? CaptureError)?.description
                    ?? String(describing: error)
                lastError = msg
                statusMessage = "녹음을 시작하지 못했어요"
                appendUILog("startRecording error \(msg)")
                appendUILog("identity \(SystemAudioRecorderIdentity.snapshot())")
                if msg.contains("TCC") || msg.contains("화면 기록") || msg.contains("거절")
                    || msg.localizedCaseInsensitiveContains("screen") {
                    Self.openScreenRecordingSettings()
                }
                refresh()
            }
        }
    }

    private func forceAbandonRecordingRowsLocally() throws {
        let store = try KnowledgeStore(path: dbPath)
        for m in try store.meetings(withStatus: .recording) {
            var copy = m
            copy.status = .abandoned
            copy.errorCode = "stale_recording_cleared"
            try store.upsertMeeting(copy)
        }
    }

    private func abandonOrphanRecordings() throws {
        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }
        _ = try client.call(JSONRPCRequest(method: RPCMethod.meetingAbandonOrphans.rawValue))
    }

    public static func openScreenRecordingSettings() {
        // macOS Ventura+ privacy pane
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
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
            appendUILog("stopRecording mid=\(mid ?? "?") path=\(artifact.path) bytes=\(artifact.byteCount)")
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
            appendUILog("stopRecording error \(error)")
        }
    }

    public func runLocalASR(meetingId: String, audioRel: String?) async {
        isProcessing = true
        statusMessage = "받아쓰는 중…"
        lastError = nil
        appendUILog("runLocalASR start \(meetingId) audio=\(audioRel ?? "?")")
        do {
            var audioPath = audioRel
            if audioPath == nil {
                let store = try KnowledgeStore(path: dbPath)
                audioPath = try store.getMeeting(id: meetingId)?.audioPath
            }
            guard let audioPath else {
                statusMessage = "녹음 파일을 찾지 못했어요"
                isProcessing = false
                appendUILog("runLocalASR no audio path")
                return
            }

            try await LocalASRService.transcribeAndComplete(
                knowledgeRoot: knowledgeRoot,
                socketPath: socketPath,
                meetingId: meetingId,
                audioRelPath: audioPath
            )
            appendUILog("runLocalASR asr.complete ok \(meetingId)")
            statusMessage = "정리하는 중…"
            refresh()

            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                refresh()
                if let row = meetings.first(where: { $0.id == meetingId }) {
                    if row.status == "review_needed" {
                        statusMessage = "확인이 필요해요"
                        isProcessing = false
                        appendUILog("pipeline review_needed \(meetingId)")
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
            statusMessage = "정리 중이에요. 목록을 확인해 주세요"
            refresh()
        } catch {
            appendUILog("runLocalASR error \(meetingId): \(error)")
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
                let store = try KnowledgeStore(path: dbPath)
                let audio = try store.getMeeting(id: meetingId)?.audioPath
                let client = UnixDomainClient(socketPath: socketPath)
                try client.connect()
                defer { client.close() }
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

    private func appendUILog(_ message: String) {
        let url = knowledgeRoot.appendingPathComponent("logs/ui.log")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
