import XCTest
@testable import KnowledgeCore

final class PipelineGraphTests: XCTestCase {
    func testOfflineHappyPathEdgesAllLegal() {
        let path: [(PipelineStatus, PipelineStatus)] = [
            (.recording, .recorded),
            (.recorded, .transcribing),
            (.transcribing, .transcribed),
            (.transcribed, .summarizing),
            (.summarizing, .summarizedCandidate),
            (.summarizedCandidate, .reviewNeeded),
            (.reviewNeeded, .commitPending),
            (.commitPending, .committed),
        ]
        for (from, to) in path {
            let ctx: GuardContext
            switch to {
            case .recorded:
                ctx = .init(hasAudioArtifact: true, audioDurationMs: 1000)
            case .transcribing:
                ctx = .init(hasAudioArtifact: true, audioDurationMs: 1000, workerSlotFree: true)
            case .transcribed:
                ctx = .init(transcriptSegmentCount: 2, hasTranscriptPath: true)
            case .summarizing:
                ctx = .init(transcriptSegmentCount: 2, hasTranscriptPath: true, workerSlotFree: true)
            case .summarizedCandidate:
                ctx = .init(stage1OK: true, stage2: .pass)
            case .reviewNeeded:
                ctx = .init(stage1OK: true, stage2: .pass, criticEnabled: false)
            case .commitPending:
                ctx = .init(stage1OK: true, humanAccepted: true)
            case .committed:
                ctx = .init(vaultFinalExists: true, indexCommittedOK: true)
            default:
                ctx = .init()
            }
            XCTAssertTrue(
                PipelineGraph.canTransition(from: from, to: to, ctx: ctx),
                "\(from.rawValue) -> \(to.rawValue)"
            )
        }
    }

    func testDefaultDenySkipAhead() {
        let ctx = GuardContext(
            hasAudioArtifact: true,
            audioDurationMs: 5000,
            transcriptSegmentCount: 5,
            hasTranscriptPath: true,
            stage1OK: true,
            stage2: .pass,
            humanAccepted: true,
            vaultFinalExists: true,
            indexCommittedOK: true
        )
        XCTAssertFalse(PipelineGraph.canTransition(from: .recording, to: .committed, ctx: ctx))
        XCTAssertFalse(PipelineGraph.canTransition(from: .transcribed, to: .committed, ctx: ctx))
        XCTAssertFalse(PipelineGraph.canTransition(from: .reviewNeeded, to: .committed, ctx: ctx))
        XCTAssertFalse(PipelineGraph.hasEdge(from: .summarizedCandidate, to: .committed))
    }

    func testCannotMarkSummarizedWithoutEvidence() {
        let noStage2 = GuardContext(stage1OK: true, stage2: nil)
        XCTAssertFalse(PipelineGraph.canTransition(from: .summarizing, to: .summarizedCandidate, ctx: noStage2))

        let fail = GuardContext(stage1OK: true, stage2: .fail)
        XCTAssertFalse(PipelineGraph.canTransition(from: .summarizing, to: .summarizedCandidate, ctx: fail))

        let warn = GuardContext(stage1OK: true, stage2: .passWithWarnings)
        XCTAssertTrue(PipelineGraph.canTransition(from: .summarizing, to: .summarizedCandidate, ctx: warn))
    }

    func testNoAutoCommitFromReview() {
        let ctx = GuardContext(stage1OK: true, humanAccepted: false)
        XCTAssertFalse(PipelineGraph.canTransition(from: .reviewNeeded, to: .commitPending, ctx: ctx))
        XCTAssertFalse(PipelineGraph.hasEdge(from: .reviewNeeded, to: .committed))
    }

    func testCriticBranch() {
        let off = GuardContext(criticEnabled: false)
        XCTAssertTrue(PipelineGraph.canTransition(from: .summarizedCandidate, to: .reviewNeeded, ctx: off))
        XCTAssertFalse(PipelineGraph.canTransition(from: .summarizedCandidate, to: .criticRunning, ctx: off))

        let on = GuardContext(criticEnabled: true)
        XCTAssertTrue(PipelineGraph.canTransition(from: .summarizedCandidate, to: .criticRunning, ctx: on))
        XCTAssertFalse(PipelineGraph.canTransition(from: .summarizedCandidate, to: .reviewNeeded, ctx: on))
    }

    func testStartRecordingSingleFlight() {
        XCTAssertTrue(PipelineGraph.canStartRecording(ctx: .init(otherRecordingActive: false, capturePreflightOK: true)))
        XCTAssertFalse(PipelineGraph.canStartRecording(ctx: .init(otherRecordingActive: true, capturePreflightOK: true)))
        XCTAssertFalse(PipelineGraph.canStartRecording(ctx: .init(otherRecordingActive: false, capturePreflightOK: false)))
    }

    func testOpenAnywayRequiresFlag() {
        XCTAssertFalse(PipelineGraph.canTransition(from: .summaryFailed, to: .reviewNeeded, ctx: .init()))
        XCTAssertTrue(PipelineGraph.canTransition(
            from: .summaryFailed,
            to: .reviewNeeded,
            ctx: .init(openAnywayAllowed: true)
        ))
    }

    func testCommittedSourcesOnlyCommitPending() {
        XCTAssertEqual(PipelineGraph.committedSources, [.commitPending])
    }

    func testTimeoutNeverSuccessHelper() {
        XCTAssertTrue(PipelineGraph.isTimeoutSuccessViolation(to: .transcribed, errorCode: "timeout"))
        XCTAssertTrue(PipelineGraph.isTimeoutSuccessViolation(to: .committed, errorCode: "timeout"))
        XCTAssertFalse(PipelineGraph.isTimeoutSuccessViolation(to: .transcribeFailed, errorCode: "timeout"))
        XCTAssertFalse(PipelineGraph.isTimeoutSuccessViolation(to: .transcribed, errorCode: nil))
    }

    func testAllStatusesHaveRawSnakeCase() {
        for status in PipelineStatus.allCases {
            XCTAssertFalse(status.rawValue.contains(where: { $0.isUppercase }), status.rawValue)
            XCTAssertFalse(status.rawValue.contains(" "), status.rawValue)
        }
    }
}
