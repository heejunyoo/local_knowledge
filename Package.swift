// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnowledgeApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KnowledgeCore", targets: ["KnowledgeCore"]),
        .library(name: "KnowledgeIndex", targets: ["KnowledgeIndex"]),
        .library(name: "KnowledgeRPC", targets: ["KnowledgeRPC"]),
        .library(name: "KnowledgeCapture", targets: ["KnowledgeCapture"]),
        .library(name: "KnowledgeWorkers", targets: ["KnowledgeWorkers"]),
        .executable(name: "knowledged", targets: ["knowledged"]),
    ],
    targets: [
        .target(
            name: "KnowledgeCore",
            path: "Packages/KnowledgeCore/Sources/KnowledgeCore"
        ),
        .testTarget(
            name: "KnowledgeCoreTests",
            dependencies: ["KnowledgeCore"],
            path: "Packages/KnowledgeCore/Tests/KnowledgeCoreTests"
        ),
        .target(
            name: "KnowledgeIndex",
            dependencies: ["KnowledgeCore"],
            path: "Packages/KnowledgeIndex/Sources/KnowledgeIndex",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "KnowledgeIndexTests",
            dependencies: ["KnowledgeIndex", "KnowledgeCore"],
            path: "Packages/KnowledgeIndex/Tests/KnowledgeIndexTests"
        ),
        .target(
            name: "KnowledgeRPC",
            dependencies: ["KnowledgeCore", "KnowledgeIndex"],
            path: "Packages/KnowledgeRPC/Sources/KnowledgeRPC"
        ),
        .testTarget(
            name: "KnowledgeRPCTests",
            dependencies: ["KnowledgeRPC", "KnowledgeIndex", "KnowledgeCore"],
            path: "Packages/KnowledgeRPC/Tests/KnowledgeRPCTests"
        ),
        .target(
            name: "KnowledgeCapture",
            dependencies: ["KnowledgeCore", "KnowledgeRPC"],
            path: "Packages/KnowledgeCapture/Sources/KnowledgeCapture"
        ),
        .testTarget(
            name: "KnowledgeCaptureTests",
            dependencies: ["KnowledgeCapture", "KnowledgeCore"],
            path: "Packages/KnowledgeCapture/Tests/KnowledgeCaptureTests"
        ),
        .target(
            name: "KnowledgeWorkers",
            dependencies: ["KnowledgeCore"],
            path: "Packages/KnowledgeWorkers/Sources/KnowledgeWorkers"
        ),
        .testTarget(
            name: "KnowledgeWorkersTests",
            dependencies: ["KnowledgeWorkers", "KnowledgeCore"],
            path: "Packages/KnowledgeWorkers/Tests/KnowledgeWorkersTests"
        ),
        .executableTarget(
            name: "knowledged",
            dependencies: ["KnowledgeRPC", "KnowledgeIndex", "KnowledgeCore"],
            path: "Sources/knowledged"
        ),
    ]
)
