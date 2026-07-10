import Foundation
import AppKit
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC
import KnowledgeCapture
import KnowledgeWorkers
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
    @Published public var committedCount: Int = 0
    @Published public var meetings: [MeetingRow] = []
    @Published public var isRecording: Bool = false
    @Published public var activeMeetingId: String?
    @Published public var statusMessage: String = "준비하고 있어요"
    @Published public var lastError: String?
    @Published public var lastVaultRel: String?
    @Published public var vaultReady: Bool = false
    @Published public var vaultDisplayPath: String = ""
    @Published public var asrEngine: String = "apple-speech"
    @Published public var llmEngine: String = "extractive-local"
    @Published public var llmStatusDetail: String = ""
    @Published public var openActionCount: Int = 0
    @Published public var dueActionCount: Int = 0
    @Published public var driftMessage: String = ""
    @Published public var searchQuery: String = ""
    @Published public var searchHits: [SearchHit] = []
    @Published public var isSearching: Bool = false
    @Published public var isIngesting: Bool = false
    @Published public var ingestStatusMessage: String?
    @Published public var ingestError: String?
    @Published public var ingestProgress: Double = 0
    @Published public var ingestProgressLabel: String = ""
    private var activeCorpus: KnowledgeCorpus?
    @Published public var sourceCountNotes: Int = 0
    @Published public var sourceCountObsidian: Int = 0
    @Published public var sourceCountFiles: Int = 0
    @Published public var sourceCountTotal: Int = 0
    @Published public var recentSources: [SourceRow] = []
    @Published public var connectedSources: [ConnectedSourceRow] = []
    @Published public var corpusTotalUnits: Int = 0
    @Published public var corpusMeetingUnits: Int = 0
    @Published public var corpusObsidianUnits: Int = 0
    @Published public var corpusNotesUnits: Int = 0
    @Published public var corpusFileUnits: Int = 0
    @Published public var chatMessages: [ChatMessage] = []
    @Published public var isChatBusy: Bool = false
    /// User-visible phase: "지식 찾는 중…" / "AI로 다듬는 중…"
    @Published public var chatBusyLabel: String = ""

    private var capture: CaptureSessionController?
    private var didReindexFTS = false
    private var didCorpusBootstrap = false
    private var pollTimer: Timer?
    private let supervisor: DaemonSupervisor
    private var asrInFlight = Set<String>()
    private var isStartingCapture = false
    private let dbPath: String
    private var appConfig: AppConfig

    public struct MeetingRow: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var status: String
        public var errorCode: String?
        public var audioPath: String?
        public var vaultPath: String?
        public var candidatePath: String?
        public var oneLine: String?
    }

    public struct SearchHit: Identifiable, Equatable {
        public var id: String { docId }
        public var docId: String
        public var title: String
        public var snippet: String
        public var sourceType: String
    }

    public struct SourceRow: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var subtitle: String
        public var kind: String
    }

    public struct ConnectedSourceRow: Identifiable, Equatable {
        public var id: String
        public var label: String
        public var kind: String
        public var detail: String
        public var enabled: Bool
    }

    public struct ChatMessage: Identifiable, Equatable {
        public enum Role: Equatable { case user, assistant }
        public var id: String
        public var role: Role
        public var text: String
        public var citations: [RAGCitation]
        /// True while a fast extractive answer may still be upgraded by cloud/7B.
        public var isRefining: Bool
        /// e.g. cloud/groq/…+cache — shown under bubble for trust/cost transparency.
        public var engine: String

        public init(
            id: String = UUID().uuidString,
            role: Role,
            text: String,
            citations: [RAGCitation] = [],
            isRefining: Bool = false,
            engine: String = ""
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.citations = citations
            self.isRefining = isRefining
            self.engine = engine
        }
    }

    public struct RAGCitation: Identifiable, Equatable {
        public var id: String
        public var unitId: String
        public var title: String
        public var sourceType: String
        public var snippet: String
    }

    public init(knowledgeRoot: URL = KnowledgePaths.defaultKnowledgeRoot) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
        self.dbPath = knowledgeRoot.appendingPathComponent("index/knowledge.db").path
        self.supervisor = DaemonSupervisor(knowledgeRoot: knowledgeRoot)
        self.appConfig = AppConfig.load(knowledgeRoot: knowledgeRoot)
        self.vaultDisplayPath = appConfig.vaultDisplayPath
        try? KnowledgePaths.ensureLayout(at: knowledgeRoot)
        refreshVaultConfig()
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
        if !vaultReady { return "vault 경로를 준비하지 못했어요 — config/app.json 확인" }
        if healthOK {
            return "ASR \(asrEngine) · 요약 \(llmEngine) · \(shortVaultLabel)"
        }
        if lastError != nil { return "다시 시도하는 중이에요" }
        return "연결을 확인하는 중이에요"
    }

    public var enginesCaption: String {
        // Plain Korean for UI; avoid engine codenames on surface
        "이 Mac에서 받아쓰고 정리해요"
    }

    private var shortVaultLabel: String {
        let p = vaultDisplayPath
        if p.count <= 42 { return p }
        return "…" + String(p.suffix(40))
    }

    public func refreshVaultConfig() {
        appConfig = AppConfig.load(knowledgeRoot: knowledgeRoot)
        vaultDisplayPath = appConfig.vaultDisplayPath
        if let err = appConfig.ensureVaultDirectory() {
            vaultReady = false
            appendUILog("vault ensure failed \(err)")
        } else {
            vaultReady = true
        }
        refreshLLMStatus()
    }

    /// Active generation engine: cloud only with keys, else **local 7B default**.
    public func refreshLLMStatus() {
        LLMProviderCatalog.ensureInstalled(knowledgeRoot: knowledgeRoot)
        let st = LLMRouter.status(knowledgeRoot: knowledgeRoot)
        llmStatusDetail = st.detail
        llmEngine = st.activeEngine
    }

    public func openVaultInFinder() {
        refreshVaultConfig()
        NSWorkspace.shared.open(appConfig.vaultURL)
    }

    public func openMeetingInFinder(vaultRel: String) {
        refreshVaultConfig()
        let url = appConfig.vaultURL.appendingPathComponent(vaultRel)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
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
        pullHealthDetails()
        if !didReindexFTS {
            didReindexFTS = true
            reindexSearchIfNeeded()
        }
        if !didCorpusBootstrap {
            didCorpusBootstrap = true
            runRetentionIfNeeded()
            runDriftAndRecovery()
            refreshActionDue()
            syncKnowledgeCorpus(includeNotes: false)
        }
    }

    /// Crash recovery + vault pointer drift (Automation phase).
    private func runDriftAndRecovery() {
        DispatchQueue.global(qos: .utility).async { [knowledgeRoot, dbPath] in
            do {
                let store = try KnowledgeStore(path: dbPath)
                let vault = AppConfig.load(knowledgeRoot: knowledgeRoot).vaultURL
                let r = try DriftChecker.run(store: store, knowledgeRoot: knowledgeRoot, vaultURL: vault)
                Task { @MainActor in
                    self.driftMessage = r.message
                    if r.recovered > 0 || !r.issues.isEmpty {
                        self.appendUILog("drift \(r.message) issues=\(r.issues.prefix(5))")
                        self.refresh()
                    }
                }
            } catch {
                Task { @MainActor in self.appendUILog("drift skip \(error)") }
            }
        }
    }

    public func refreshActionDue() {
        DispatchQueue.global(qos: .utility).async { [dbPath] in
            do {
                let store = try KnowledgeStore(path: dbPath)
                let open = try store.openActionItems()
                let items = open.map {
                    ActionDueNotifier.Item(id: $0.id, meetingId: $0.meetingId, text: $0.text, dueOn: $0.dueOn)
                }
                let due = ActionDueNotifier.dueSoon(items: items, withinDays: 7)
                Task { @MainActor in
                    self.openActionCount = open.count
                    self.dueActionCount = due.count
                    #if canImport(UserNotifications)
                    if !due.isEmpty {
                        ActionDueNotifier.requestAuthAndNotify(items: due)
                    }
                    #endif
                }
            } catch {
                Task { @MainActor in self.appendUILog("action due skip \(error)") }
            }
        }
    }

    /// Quiet retention (abandoned age + optional committed audio age).
    private func runRetentionIfNeeded() {
        let cfg = AppConfig.load(knowledgeRoot: knowledgeRoot)
        guard cfg.retentionPurgeOnLaunch else { return }
        DispatchQueue.global(qos: .utility).async { [knowledgeRoot, dbPath] in
            do {
                let store = try KnowledgeStore(path: dbPath)
                let r = try MeetingCleanup.runRetentionPolicy(
                    store: store,
                    knowledgeRoot: knowledgeRoot,
                    config: cfg
                )
                if r.deletedMeetings > 0 || r.deletedFiles > 0 {
                    Task { @MainActor in
                        self.appendUILog("retention \(r.message)")
                        self.refresh()
                        self.refreshSourceStats()
                    }
                }
            } catch {
                Task { @MainActor in
                    self.appendUILog("retention skip \(error)")
                }
            }
        }
    }

    /// Parse extended health (engines, vault) from daemon.
    private func pullHealthDetails() {
        do {
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }
            let res = try client.call(JSONRPCRequest(method: RPCMethod.health.rawValue))
            guard let obj = res.result, case let .object(map) = obj else { return }
            if case let .string(a) = map["asr_engine"] { asrEngine = a }
            // llm_engine from daemon is coarse — cascade status is SoT (cloud keys / local 7B)
            if case let .string(vp) = map["vault_path"], !vp.isEmpty {
                vaultDisplayPath = vp
            }
            if case let .bool(ok) = map["vault_ok"] {
                vaultReady = ok || vaultReady
            }
            refreshLLMStatus()
        } catch {
            refreshLLMStatus()
        }
    }

    private func reindexSearchIfNeeded() {
        do {
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }
            let res = try client.call(JSONRPCRequest(method: RPCMethod.searchReindex.rawValue))
            if case let .number(n) = res.result?["reindexed"] {
                appendUILog("search.reindex \(Int(n))")
            }
        } catch {
            appendUILog("search.reindex skip \(error)")
        }
    }

    public func runSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchHits = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            if !healthOK { bootstrapBackendIfNeeded() }
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }
            let res = try client.call(JSONRPCRequest(
                method: RPCMethod.search.rawValue,
                params: .object([
                    "q": .string(q),
                    "limit": .number(20),
                ])
            ))
            if let err = res.error {
                lastError = err.message
                searchHits = []
                return
            }
            var hits: [SearchHit] = []
            if case let .object(root) = res.result,
               case let .array(arr) = root["hits"] {
                for item in arr {
                    guard case let .object(h) = item,
                          case let .string(id) = h["doc_id"] else { continue }
                    let title: String
                    if case let .string(t) = h["title"] { title = t } else { title = id }
                    let snip: String
                    if case let .string(s) = h["snippet"] { snip = s } else { snip = "" }
                    let st: String
                    if case let .string(s) = h["source_type"] { st = s } else { st = "meeting" }
                    hits.append(SearchHit(docId: id, title: title, snippet: snip, sourceType: st))
                }
            }
            searchHits = hits
            appendUILog("search q=\(q) hits=\(hits.count)")
        } catch {
            lastError = String(describing: error)
            searchHits = []
        }
    }

    public func openSearchHit(_ hit: SearchHit) {
        if hit.sourceType == "meeting" {
            if let row = meetings.first(where: { $0.id == hit.docId }), let vp = row.vaultPath {
                openMeetingInFinder(vaultRel: vp)
                return
            }
            if let store = try? KnowledgeStore(path: dbPath),
               let m = try? store.getMeeting(id: hit.docId),
               let vp = m.vaultPath {
                openMeetingInFinder(vaultRel: vp)
            }
            return
        }
        // Resolve pointer → open file path or vault rel
        if let store = try? KnowledgeStore(path: dbPath),
           let ptrs = try? store.listSourcePointers(limit: 200),
           let p = ptrs.first(where: { $0.id == hit.docId }) {
            if p.sourceType == "obsidian", let rel = p.vaultRelPath {
                openMeetingInFinder(vaultRel: rel)
            } else if p.sourceType == "file" {
                let url = URL(fileURLWithPath: p.externalId)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } else if p.sourceType == "notes" {
                // Best effort: open Notes app
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
            }
        }
    }

    // MARK: - Knowledge corpus (meetings + connected sources)

    public func refreshSourceStats() {
        do {
            let store = try KnowledgeStore(path: dbPath)
            corpusMeetingUnits = try store.countKnowledgeUnits(sourceType: "meeting")
            corpusNotesUnits = try store.countKnowledgeUnits(sourceType: "notes")
            corpusObsidianUnits = try store.countKnowledgeUnits(sourceType: "obsidian")
            corpusFileUnits = try store.countKnowledgeUnits(sourceType: "file")
            corpusTotalUnits = try store.countKnowledgeUnits()
            sourceCountNotes = corpusNotesUnits
            sourceCountObsidian = corpusObsidianUnits
            sourceCountFiles = corpusFileUnits
            sourceCountTotal = corpusTotalUnits
            connectedSources = try store.listConnectedSources().map { s in
                let sync = s.lastSyncAt.map { "동기화 \($0)" } ?? "아직 동기화 안 됨"
                let path = s.rootPath ?? "(시스템)"
                return ConnectedSourceRow(
                    id: s.id,
                    label: s.label ?? s.sourceType,
                    kind: s.sourceType,
                    detail: "\(path) · unit \(s.unitCount) · \(sync)",
                    enabled: s.enabled
                )
            }
            recentSources = try store.listSourcePointers(limit: 12).map { p in
                SourceRow(
                    id: p.id,
                    title: p.title ?? p.externalId,
                    subtitle: p.externalId,
                    kind: p.sourceType
                )
            }
        } catch {
            appendUILog("source stats \(error)")
        }
    }

    public func cancelCorpusSync() {
        activeCorpus?.requestCancel()
        ingestStatusMessage = "취소 요청 중…"
    }

    private func applyCorpusProgress(_ p: KnowledgeCorpus.Progress) {
        ingestProgress = p.fraction
        ingestProgressLabel = p.label
        ingestStatusMessage = p.label
    }

    private func beginIngest(status: String) {
        isIngesting = true
        ingestError = nil
        ingestProgress = 0
        ingestProgressLabel = status
        ingestStatusMessage = status
    }

    private func endIngest() {
        isIngesting = false
        activeCorpus = nil
        if ingestProgress >= 0.999 {
            ingestProgress = 1
        }
    }

    /// Full corpus sync. Notes require UI process (Automation TCC).
    public func syncKnowledgeCorpus(includeNotes: Bool) {
        guard !isIngesting else { return }
        beginIngest(status: "지식 코퍼스 동기화 준비…")
        refreshVaultConfig()
        let root = knowledgeRoot
        let vaultPath = vaultDisplayPath
        let db = dbPath
        let wantNotes = includeNotes

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let store = try KnowledgeStore(path: db)
                let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
                let corpus = KnowledgeCorpus(store: store, knowledgeRoot: root, vaultURL: vault)
                await MainActor.run { self.activeCorpus = corpus }
                try corpus.ensureDefaultConnections()
                let progress: KnowledgeCorpus.ProgressHandler = { p in
                    Task { @MainActor in self.applyCorpusProgress(p) }
                }
                let report: KnowledgeCorpus.SyncReport
                if wantNotes {
                    // JXA must stay on main for TCC; fetch notes first on main then index bg
                    let notes = try await MainActor.run {
                        try AppleNotesImport.fetchNotes(limit: 500)
                    }
                    report = try corpus.syncAll(notesProvider: { notes }, progress: progress)
                } else {
                    report = try corpus.syncAll(notesProvider: nil, progress: progress)
                }
                await MainActor.run {
                    self.ingestStatusMessage = report.message
                    self.ingestProgress = 1
                    self.ingestProgressLabel = "완료"
                    self.appendUILog("corpus.sync \(report.message)")
                    self.refreshSourceStats()
                    self.endIngest()
                }
            } catch {
                await MainActor.run {
                    let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    self.ingestError = msg
                    self.appendUILog("corpus.sync error \(error)")
                    self.endIngest()
                }
            }
        }
    }

    public func connectAndSyncAppleNotes() {
        guard !isIngesting else { return }
        beginIngest(status: "Apple Notes 연결…")
        refreshVaultConfig()
        let root = knowledgeRoot
        let vaultPath = vaultDisplayPath
        let db = dbPath
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let notes = try await MainActor.run {
                    try AppleNotesImport.fetchNotes(limit: 500)
                }
                let store = try KnowledgeStore(path: db)
                let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
                let corpus = KnowledgeCorpus(store: store, knowledgeRoot: root, vaultURL: vault)
                await MainActor.run { self.activeCorpus = corpus }
                try corpus.connectAppleNotes(enabled: true)
                let report = try corpus.syncAll(
                    notesProvider: { notes },
                    progress: { p in Task { @MainActor in self.applyCorpusProgress(p) } }
                )
                await MainActor.run {
                    self.ingestStatusMessage = report.message
                    self.ingestProgress = 1
                    self.appendUILog("corpus.notes \(report.message)")
                    self.refreshSourceStats()
                    self.endIngest()
                }
            } catch {
                await MainActor.run {
                    self.ingestError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    self.appendUILog("corpus.notes error \(error)")
                    self.endIngest()
                }
            }
        }
    }

    public func connectFolder(asObsidian: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = asObsidian ? "연결할 Obsidian vault 폴더" : "지식으로 연결할 폴더"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !isIngesting else { return }
        beginIngest(status: "폴더 연결: \(url.lastPathComponent)")
        refreshVaultConfig()
        let root = knowledgeRoot
        let vaultPath = vaultDisplayPath
        let db = dbPath
        let folderPath = url.path
        let label = url.lastPathComponent
        let obs = asObsidian

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let store = try KnowledgeStore(path: db)
                let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
                let corpus = KnowledgeCorpus(store: store, knowledgeRoot: root, vaultURL: vault)
                await MainActor.run { self.activeCorpus = corpus }
                let connected = try corpus.connectFolder(path: folderPath, label: label, asObsidian: obs)
                // Only index this folder (not entire corpus) — progress bar stays meaningful
                let n = try corpus.syncSource(id: connected.id) { p in
                    Task { @MainActor in self.applyCorpusProgress(p) }
                }
                await MainActor.run {
                    self.ingestStatusMessage = "\(label): \(n)개 파일 처리 완료"
                    self.ingestProgress = 1
                    self.appendUILog("corpus.folder \(folderPath) n=\(n)")
                    self.refreshSourceStats()
                    self.endIngest()
                }
            } catch {
                await MainActor.run {
                    self.ingestError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    self.appendUILog("corpus.folder error \(error)")
                    self.endIngest()
                }
            }
        }
    }

    public func connectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "지식 코퍼스에 연결할 텍스트 파일"
        guard panel.runModal() == .OK else { return }
        guard !isIngesting else { return }
        beginIngest(status: "파일 연결…")
        refreshVaultConfig()
        let root = knowledgeRoot
        let vaultPath = vaultDisplayPath
        let db = dbPath
        let paths = panel.urls.map(\.path)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let store = try KnowledgeStore(path: db)
                let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
                let corpus = KnowledgeCorpus(store: store, knowledgeRoot: root, vaultURL: vault)
                await MainActor.run { self.activeCorpus = corpus }
                var done = 0
                for (i, path) in paths.enumerated() {
                    await MainActor.run {
                        self.applyCorpusProgress(.init(
                            phase: "파일 연결",
                            completed: i,
                            total: paths.count,
                            currentName: URL(fileURLWithPath: path).lastPathComponent
                        ))
                    }
                    let connected = try corpus.connectFile(path: path)
                    done += try corpus.syncSource(id: connected.id)
                }
                let finalDone = done
                await MainActor.run {
                    self.ingestStatusMessage = "파일 \(finalDone)개 처리 완료"
                    self.ingestProgress = 1
                    self.appendUILog("corpus.files n=\(finalDone)")
                    self.refreshSourceStats()
                    self.endIngest()
                }
            } catch {
                await MainActor.run {
                    self.ingestError = String(describing: error)
                    self.appendUILog("corpus.files error \(error)")
                    self.endIngest()
                }
            }
        }
    }

    // Legacy names kept for verify-field string contracts
    public func importAppleNotes() { connectAndSyncAppleNotes() }
    public func importObsidianVault() { syncKnowledgeCorpus(includeNotes: false) }

    // MARK: - Cleanup / retention

    /// Delete meeting from index + local audio/transcript/summary (vault note kept).
    public func deleteMeeting(id: String) {
        do {
            let store = try KnowledgeStore(path: dbPath)
            let r = try MeetingCleanup.deleteMeeting(
                id: id,
                store: store,
                knowledgeRoot: knowledgeRoot,
                deleteLocalFiles: true
            )
            if activeMeetingId == id {
                isRecording = false
                activeMeetingId = nil
                capture = nil
            }
            statusMessage = r.message
            appendUILog("meeting.delete \(id) files=\(r.deletedFiles)")
            refresh()
            refreshSourceStats()
        } catch {
            lastError = String(describing: error)
            appendUILog("meeting.delete error \(error)")
        }
    }

    /// Clear abandoned/failed meetings and free disk.
    public func purgeAbandonedMeetings() {
        do {
            let store = try KnowledgeStore(path: dbPath)
            let cfg = AppConfig.load(knowledgeRoot: knowledgeRoot)
            // Manual purge: all abandoned (days=0). Policy auto-purge uses config days.
            let r = try MeetingCleanup.purgeAbandoned(
                store: store,
                knowledgeRoot: knowledgeRoot,
                olderThanDays: 0
            )
            _ = cfg
            statusMessage = r.message
            ingestStatusMessage = r.message
            appendUILog("meeting.purge \(r.message)")
            refresh()
            refreshSourceStats()
        } catch {
            lastError = String(describing: error)
            appendUILog("meeting.purge error \(error)")
        }
    }

    public var abandonedMeetingCount: Int {
        meetings.filter {
            $0.status == "abandoned" || $0.status.contains("fail")
        }.count
    }

    // MARK: - RAG Chat (fast extractive first, optional LLM refine)

    public func askKnowledge(question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isChatBusy else { return }
        chatMessages.append(ChatMessage(role: .user, text: q))
        isChatBusy = true
        chatBusyLabel = "지식 찾는 중…"
        let db = dbPath
        let root = knowledgeRoot
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let store = try KnowledgeStore(path: db)
                let cfg = AppConfig.load(knowledgeRoot: root)

                // 1) Instant path — never wait on 7B for first paint
                let fast = try KnowledgeRAG.askFast(question: q, store: store, topK: 8)
                let cites = fast.citations.map {
                    RAGCitation(
                        id: $0.id,
                        unitId: $0.unitId,
                        title: $0.title,
                        sourceType: $0.sourceType,
                        snippet: $0.snippet
                    )
                }
                let assistantId = UUID().uuidString
                let willRefine = cfg.ragUseLlama
                    && !fast.citations.isEmpty
                    && (LocalLLM.isAvailable(knowledgeRoot: root)
                        || LLMSecrets.hasAnyCloudKey(
                            knowledgeRoot: root,
                            catalog: LLMProviderCatalog.load(knowledgeRoot: root)
                        ))

                await MainActor.run {
                    self.chatMessages.append(ChatMessage(
                        id: assistantId,
                        role: .assistant,
                        text: fast.answer,
                        citations: cites,
                        isRefining: willRefine,
                        engine: fast.engine
                    ))
                    self.isChatBusy = false
                    self.chatBusyLabel = ""
                    self.appendUILog("rag.fast cites=\(cites.count) engine=\(fast.engine) refine=\(willRefine)")
                }

                // 2) At most one refine (cloud/7B) — disk cache inside LLMRouter avoids re-spend
                guard willRefine else { return }
                await MainActor.run {
                    if let i = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        self.chatMessages[i].isRefining = true
                    }
                }
                let refined = KnowledgeRAG.refine(
                    question: q,
                    citations: fast.citations,
                    knowledgeRoot: root,
                    useLlama: cfg.ragUseLlama
                )
                await MainActor.run {
                    guard let i = self.chatMessages.firstIndex(where: { $0.id == assistantId }) else { return }
                    if let refined, refined.answer != self.chatMessages[i].text {
                        self.chatMessages[i].text = refined.answer
                        self.chatMessages[i].engine = refined.engine
                        self.chatMessages[i].isRefining = false
                        self.appendUILog("rag.refine engine=\(refined.engine)")
                    } else {
                        self.chatMessages[i].isRefining = false
                        self.appendUILog("rag.refine keep extractive")
                    }
                }
            } catch {
                await MainActor.run {
                    self.chatMessages.append(ChatMessage(
                        role: .assistant,
                        text: "답변 중 오류: \(error.localizedDescription)"
                    ))
                    self.isChatBusy = false
                    self.chatBusyLabel = ""
                    self.appendUILog("rag.ask error \(error)")
                }
            }
        }
    }

    public func openRAGCitation(_ c: RAGCitation) {
        // Reuse search open path by synthesizing a hit
        openSearchHit(SearchHit(
            docId: c.unitId,
            title: c.title,
            snippet: c.snippet,
            sourceType: c.sourceType
        ))
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
                    audioPath: m.audioPath,
                    vaultPath: m.vaultPath,
                    candidatePath: m.candidatePath,
                    oneLine: Self.loadOneLine(
                        knowledgeRoot: knowledgeRoot,
                        candidatePath: m.candidatePath
                    )
                )
            }
            // Stable order: newest activity first by id is weak; prefer review then recent list as-is
            meetings.sort { a, b in
                rank(a.status) < rank(b.status)
            }
            reviewCount = rows.filter { $0.status == .reviewNeeded }.count
            recordingCount = rows.filter { $0.status == .recording }.count
            committedCount = rows.filter { $0.status == .committed }.count
            appendUILog("refresh meetings=\(meetings.count) review=\(reviewCount) committed=\(committedCount)")
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
                // Do not auto-open System Settings — Settings ON + ad-hoc CDHash drift is common;
                // opening Settings repeatedly is noise, not a fix.
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
        lastVaultRel = nil
        refreshVaultConfig()
        if !vaultReady {
            lastError = "vault 경로를 쓸 수 없어요: \(vaultDisplayPath)"
            statusMessage = "저장하지 못했어요"
            return
        }
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
                appendUILog("acceptReview error \(err.message)")
                return
            }
            if case let .object(obj) = res.result,
               case let .string(rel) = obj["vault_rel"] {
                lastVaultRel = rel
                statusMessage = "저장했어요 · \(rel)"
                appendUILog("acceptReview ok \(meetingId) vault=\(rel)")
            } else {
                statusMessage = "저장했어요"
                appendUILog("acceptReview ok \(meetingId)")
            }
            refresh()
            refreshActionDue()
        } catch {
            lastError = String(describing: error)
            statusMessage = "저장하지 못했어요"
            appendUILog("acceptReview exception \(error)")
        }
    }

    private static func loadOneLine(knowledgeRoot: URL, candidatePath: String?) -> String? {
        guard let rel = candidatePath else { return nil }
        let url = knowledgeRoot.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = obj["one_line_summary"] as? String,
              !line.isEmpty else { return nil }
        return line
    }

    private func rank(_ status: String) -> Int {
        switch status {
        case "review_needed": return 0
        case "recording": return 1
        case "recorded", "transcribing", "transcribed", "summarizing": return 2
        case let s where s.contains("fail"): return 3
        case "committed": return 4
        default: return 5
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

    /// Append a line to logs/ui.log (settings and diagnostics).
    public func appendUILog(_ message: String) {
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
