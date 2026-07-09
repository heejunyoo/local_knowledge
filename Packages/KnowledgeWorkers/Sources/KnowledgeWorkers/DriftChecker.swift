import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Lightweight drift detection: vault pointers, orphan statuses, corpus parity.
public enum DriftChecker {
    public struct Report: Equatable, Sendable {
        public var issues: [String]
        public var recovered: Int
        public var message: String

        public init(issues: [String], recovered: Int, message: String) {
            self.issues = issues
            self.recovered = recovered
            self.message = message
        }
    }

    public static func run(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        vaultURL: URL
    ) throws -> Report {
        var issues: [String] = []
        var recovered = 0

        // 1) Crash recovery R1–R6 for sticky statuses
        recovered += try applyCrashRecovery(store: store, knowledgeRoot: knowledgeRoot)

        // 2) Committed meetings: vault file must exist
        for m in try store.meetings(withStatus: .committed) {
            guard let rel = m.vaultPath else {
                issues.append("committed_missing_vault_path:\(m.id)")
                continue
            }
            let url = vaultURL.appendingPathComponent(rel)
            if !FileManager.default.fileExists(atPath: url.path) {
                issues.append("dead_vault_pointer:\(m.id):\(rel)")
            }
        }

        // 3) review_needed without candidate
        for m in try store.meetings(withStatus: .reviewNeeded) {
            if m.candidatePath == nil {
                issues.append("review_without_candidate:\(m.id)")
            }
        }

        let msg: String
        if issues.isEmpty && recovered == 0 {
            msg = "drift: clean"
        } else if issues.isEmpty {
            msg = "drift: recovered \(recovered)"
        } else {
            msg = "drift: \(issues.count) issue(s), recovered \(recovered)"
        }
        return Report(issues: issues, recovered: recovered, message: msg)
    }

    @discardableResult
    public static func applyCrashRecovery(store: KnowledgeStore, knowledgeRoot: URL) throws -> Int {
        var n = 0
        let sticky: [PipelineStatus] = [.recording, .transcribing, .summarizing, .criticRunning, .commitPending]
        for st in sticky {
            for m in try store.meetings(withStatus: st) {
                let audioURL = m.audioPath.map { knowledgeRoot.appendingPathComponent($0) }
                let hasAudio = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                var age: Int?
                if let audioURL, hasAudio,
                   let vals = try? audioURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let mod = vals.contentModificationDate {
                    age = Int(Date().timeIntervalSince(mod))
                }
                let snap = MeetingRecoverySnapshot(
                    status: m.status,
                    hasAudioArtifact: hasAudio,
                    audioDurationMs: m.audioDurationMs ?? 0,
                    audioMtimeAgeSeconds: age,
                    heartbeatFresh: false,
                    stageAttempts: m.stageAttempts
                )
                let (_, action) = CrashRecovery.evaluate(snap)
                guard case let .transition(to, reason) = action else { continue }
                let ctx = GuardContext(
                    hasAudioArtifact: hasAudio,
                    audioDurationMs: m.audioDurationMs ?? 0
                )
                if let dest = CrashRecovery.applyTransitionIfLegal(from: m.status, action: action, ctx: ctx) {
                    _ = try? store.transition(
                        meetingId: m.id,
                        to: dest,
                        ctx: ctx,
                        errorCode: reason,
                        event: "recovery.\(reason)"
                    )
                    n += 1
                } else if to == .recorded || to == .recordFailed || to == .transcribeFailed
                            || to == .summaryFailed || to == .criticFailed {
                    // Best-effort: sticky worker states may lack full guard context after crash
                    var copy = m
                    copy.status = to
                    copy.errorCode = reason
                    copy.updatedAt = ISO8601DateFormatter().string(from: Date())
                    try? store.upsertMeeting(copy)
                    n += 1
                }
            }
        }
        return n
    }
}
