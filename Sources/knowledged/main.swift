import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC

// knowledged — pipeline daemon (PR-04)
// Usage: knowledged [--root ~/Knowledge] [--socket path]

func expand(_ path: String) -> String {
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2))).path
    }
    return path
}

var root = KnowledgePaths.defaultKnowledgeRoot.path
var socketRel = "cache/daemon.sock"

var args = Array(CommandLine.arguments.dropFirst())
while let a = args.first {
    args.removeFirst()
    switch a {
    case "--root":
        root = expand(args.removeFirst())
    case "--socket":
        socketRel = args.removeFirst()
    case "--help", "-h":
        print("knowledged [--root PATH] [--socket REL_OR_ABS]")
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
let runtime = DaemonRuntime(store: store, socketPath: socketPath)

signal(SIGINT) { _ in
    fputs("knowledged: shutting down\n", stderr)
    exit(0)
}

try runtime.startListening()
fputs("knowledged \(PipelineService.version) listening on \(socketPath)\n", stderr)
try runtime.runAcceptLoop()
