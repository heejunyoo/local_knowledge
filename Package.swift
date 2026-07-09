// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnowledgeApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KnowledgeCore", targets: ["KnowledgeCore"]),
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
    ]
)
