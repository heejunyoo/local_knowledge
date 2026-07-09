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
        .library(name: "KnowledgeUI", targets: ["KnowledgeUI"]),
        .executable(name: "knowledged", targets: ["knowledged"]),
        .executable(name: "KnowledgeApp", targets: ["KnowledgeApp"]),
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
            dependencies: ["KnowledgeCore", "KnowledgeIndex", "KnowledgeWorkers"],
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
            dependencies: ["KnowledgeCore", "KnowledgeIndex"],
            path: "Packages/KnowledgeWorkers/Sources/KnowledgeWorkers"
        ),
        .testTarget(
            name: "KnowledgeWorkersTests",
            dependencies: ["KnowledgeWorkers", "KnowledgeCore", "KnowledgeIndex"],
            path: "Packages/KnowledgeWorkers/Tests/KnowledgeWorkersTests"
        ),
        .target(
            name: "KnowledgeUI",
            dependencies: [
                "KnowledgeCore",
                "KnowledgeIndex",
                "KnowledgeRPC",
                "KnowledgeCapture",
            ],
            path: "Packages/KnowledgeUI/Sources/KnowledgeUI"
        ),
        .testTarget(
            name: "KnowledgeUITests",
            dependencies: ["KnowledgeUI"],
            path: "Packages/KnowledgeUI/Tests/KnowledgeUITests"
        ),
        .executableTarget(
            name: "knowledged",
            dependencies: [
                "KnowledgeRPC",
                "KnowledgeIndex",
                "KnowledgeCore",
                "KnowledgeWorkers",
            ],
            path: "Sources/knowledged"
        ),
        .executableTarget(
            name: "KnowledgeApp",
            dependencies: [
                "KnowledgeUI",
                "KnowledgeCore",
            ],
            path: "Sources/KnowledgeApp",
            exclude: ["Info.plist"]
        ),
    ]
)
