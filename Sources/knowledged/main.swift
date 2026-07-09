import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC
import KnowledgeWorkers
import KnowledgeGateway

// knowledged — pipeline daemon + optional mobile HTTP gateway
// Usage: knowledged [--root ~/Knowledge] [--socket path] [--http-port 8741] [--pair] [--no-pipeline]

func expand(_ path: String) -> String {
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2))).path
    }
    return path
}

var root = KnowledgePaths.defaultKnowledgeRoot.path
var socketRel = "cache/daemon.sock"
var enablePipeline = true
var httpPort: UInt16? = nil
var emitPair = false

var args = Array(CommandLine.arguments.dropFirst())
while let a = args.first {
    args.removeFirst()
    switch a {
    case "--root":
        root = expand(args.removeFirst())
    case "--socket":
        socketRel = args.removeFirst()
    case "--no-pipeline":
        enablePipeline = false
    case "--http-port":
        httpPort = UInt16(args.removeFirst()) ?? 8741
    case "--pair":
        emitPair = true
        if httpPort == nil { httpPort = 8741 }
    case "--help", "-h":
        print("knowledged [--root PATH] [--socket REL] [--http-port 8741] [--pair] [--no-pipeline]")
        exit(0)
    default:
        fputs("unknown arg \(a)\n", stderr)
        exit(2)
    }
}

let rootURL = URL(fileURLWithPath: expand(root), isDirectory: true)
try KnowledgePaths.ensureLayout(at: rootURL)
let dbPath = rootURL.appendingPathComponent("index/knowledge.db").path
let socketPath: String
if socketRel.hasPrefix("/") {
    socketPath = socketRel
} else {
    socketPath = rootURL.appendingPathComponent(socketRel).path
}

let store = try KnowledgeStore(path: dbPath)
let vault = PipelineService.resolveVaultPath(knowledgeRoot: rootURL)
let pipeline = PipelineService(store: store, knowledgeRoot: rootURL, vaultPath: vault)
let runtime = DaemonRuntime(
    store: store,
    knowledgeRoot: rootURL,
    socketPath: socketPath
)

let appConfig = AppConfig.load(knowledgeRoot: rootURL)
let language = appConfig.asrLanguage

let runner = OfflinePipelineRunner(
    store: store,
    knowledgeRoot: rootURL,
    language: language
)

signal(SIGINT) { _ in
    fputs("knowledged: shutting down\n", stderr)
    exit(0)
}

if appConfig.retentionPurgeOnLaunch {
    do {
        let r = try MeetingCleanup.runRetentionPolicy(
            store: store,
            knowledgeRoot: rootURL,
            config: appConfig
        )
        if r.deletedMeetings > 0 || r.deletedFiles > 0 {
            fputs("knowledged: retention \(r.message)\n", stderr)
        }
    } catch {
        fputs("knowledged: retention skip \(error)\n", stderr)
    }
}

// Mobile / Core HTTP gateway (Tailscale). Must retain server for process lifetime.
var mobileGateway: MobileHTTPServer?
if let port = httpPort {
    let gw = MobileHTTPServer(
        port: port,
        knowledgeRoot: rootURL,
        store: store,
        pipeline: pipeline,
        coreName: Host.current().localizedName ?? "knowledge-core"
    )
    try gw.start()
    if emitPair {
        _ = try gw.emitPairCode()
    }
    mobileGateway = gw
    fputs("knowledged: mobile gateway on port \(port) — use Tailscale IP from phone\n", stderr)
}
// prevent optimizer dropping retain
withExtendedLifetime(mobileGateway) { _ in }

try runtime.startListening()
fputs("knowledged \(PipelineService.version) listening on \(socketPath)\n", stderr)

if enablePipeline {
    fputs("knowledged: pipeline tick (ASR→summary→review_needed)\n", stderr)
    DispatchQueue.global(qos: .utility).async {
        while true {
            do {
                _ = try runner.tick()
            } catch {
                fputs("pipeline tick error: \(error)\n", stderr)
            }
            Thread.sleep(forTimeInterval: 1.5)
        }
    }
}

try runtime.runAcceptLoop()
