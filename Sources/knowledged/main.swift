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

// Language from app.json if present
var language = "ko"
let appJSON = rootURL.appendingPathComponent("config/app.json")
if let data = try? Data(contentsOf: appJSON),
   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let asr = obj["asr"] as? [String: Any],
   let lang = asr["language"] as? String {
    language = lang
}

let runner = OfflinePipelineRunner(
    store: store,
    knowledgeRoot: rootURL,
    language: language
)

signal(SIGINT) { _ in
    fputs("knowledged: shutting down\n", stderr)
    exit(0)
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
