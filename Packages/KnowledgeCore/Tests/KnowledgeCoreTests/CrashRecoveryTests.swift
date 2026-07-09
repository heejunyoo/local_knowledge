import XCTest
@testable import KnowledgeCore

final class CrashRecoveryTests: XCTestCase {
    func testR1EmptyRecording() {
        let snap = MeetingRecoverySnapshot(status: .recording, hasAudioArtifact: false, audioDurationMs: 0)
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r1OrphanEmpty)
        XCTAssertEqual(action, .transition(to: .recordFailed, reason: "orphan_empty"))

        let ctx = GuardContext()
        XCTAssertEqual(
            CrashRecovery.applyTransitionIfLegal(from: .recording, action: action, ctx: ctx),
            .recordFailed
        )
    }

    func testR2StaleWithAudio() {
        let snap = MeetingRecoverySnapshot(
            status: .recording,
            hasAudioArtifact: true,
            audioDurationMs: 12_000,
            audioMtimeAgeSeconds: 180,
            heartbeatFresh: false
        )
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r2StaleRecording)
        guard case let .transition(to, reason) = action else {
            return XCTFail("expected transition")
        }
        XCTAssertEqual(to, .recorded)
        XCTAssertEqual(reason, "stale_recording_no_heartbeat")

        let ctx = GuardContext(hasAudioArtifact: true, audioDurationMs: 12_000)
        XCTAssertEqual(
            CrashRecovery.applyTransitionIfLegal(from: .recording, action: action, ctx: ctx),
            .recorded
        )
    }

    func testR2NotAppliedWhenHeartbeatFresh() {
        let snap = MeetingRecoverySnapshot(
            status: .recording,
            hasAudioArtifact: true,
            audioDurationMs: 12_000,
            audioMtimeAgeSeconds: 180,
            heartbeatFresh: true
        )
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .none)
    }

    func testR3MaxAttemptsFails() {
        let snap = MeetingRecoverySnapshot(
            status: .transcribing,
            hasAudioArtifact: true,
            audioDurationMs: 1000,
            stageAttempts: 2,
            maxStageAttempts: 2
        )
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r3ReenterOrFail)
        XCTAssertEqual(action, .transition(to: .transcribeFailed, reason: "max_stage_attempts"))
    }

    func testR3ReenterWhenAttemptsRemain() {
        let snap = MeetingRecoverySnapshot(
            status: .summarizing,
            stageAttempts: 0,
            maxStageAttempts: 2
        )
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r3ReenterOrFail)
        XCTAssertEqual(action, .reenterWork(status: .summarizing))
    }

    func testR4CommitPending() {
        let snap = MeetingRecoverySnapshot(status: .commitPending)
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r4CommitReconcile)
        XCTAssertEqual(action, .reconcileCommit)
    }

    func testR5OrphanPath() {
        let snap = MeetingRecoverySnapshot(status: .abandoned, orphanAudioPath: "/tmp/x.m4a")
        let (rule, action) = CrashRecovery.evaluate(snap)
        XCTAssertEqual(rule, .r5OrphanAudio)
        XCTAssertEqual(action, .quarantineOrphanAudio(path: "/tmp/x.m4a"))
    }
}
