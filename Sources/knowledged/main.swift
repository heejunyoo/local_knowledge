import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC
import KnowledgeWorkers

// knowledged — pipeline daemon
// Usage: knowledged [--root ~/Knowledge] [--socket path] [--no-pipeline]

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
    case "--help", "-h":
        print("knowledged [--root PATH] [--socket REL_OR_ABS] [--no-pipeline]")
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
let runtime = DaemonRuntime(
    store: store,
    knowledgeRoot: rootURL,
    socketPath: socketPath
)

// Config from app.json (language + retention)
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

// Quiet retention once at launch (before accept loop)
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
