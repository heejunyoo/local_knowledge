import XCTest
@testable import KnowledgeCore

final class ScenarioRunnerTests: XCTestCase {
    func testBundledScenariosAllPass() throws {
        let dir = try scenariosDirectory()
        let scenarios = try ScenarioRunner.loadDirectory(dir)
        XCTAssertGreaterThanOrEqual(scenarios.count, 4, "expected S02/S02b/S05/S11/S12")

        let results = ScenarioRunner.runAll(scenarios)
        for result in results {
            XCTAssertTrue(
                result.passed,
                "\(result.scenarioId) failed: \(result.failures.joined(separator: "; "))"
            )
        }
    }

    func testScenarioJSONRoundTrip() throws {
        let dir = try scenariosDirectory()
        let url = dir.appendingPathComponent("S11_no_wildcard_committed.json")
        let scenario = try ScenarioRunner.load(from: url)
        XCTAssertEqual(scenario.id, "S11")
        let data = try JSONEncoder().encode(scenario)
        let decoded = try JSONDecoder().decode(EvalScenario.self, from: data)
        XCTAssertEqual(decoded.id, scenario.id)
        XCTAssertEqual(decoded.assertions.count, scenario.assertions.count)
    }

    func testS12TimeoutAssertionSemantics() {
        let pass = EvalScenario(
            id: "t-pass",
            title: "t",
            kind: .timeout,
            assertions: [
                .timeoutPolicy(to: "transcribe_failed", expectViolation: false),
                .timeoutPolicy(to: "committed", expectViolation: true),
            ]
        )
        XCTAssertTrue(ScenarioRunner.run(pass).passed)

        let fail = EvalScenario(
            id: "t-fail",
            title: "t",
            kind: .timeout,
            assertions: [
                .timeoutPolicy(to: "committed", expectViolation: false),
            ]
        )
        let result = ScenarioRunner.run(fail)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failures.contains { $0.contains("committed") })
    }

    private func scenariosDirectory() throws -> URL {
        // .../Packages/KnowledgeCore/Tests/KnowledgeCoreTests/ThisFile.swift → repo root
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("evals/scenarios", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("scenarios dir not found at \(dir.path)")
        }
        return dir
    }
}
