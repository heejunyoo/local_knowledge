import Foundation

/// Well-known daemon methods (MVP surface).
public enum RPCMethod: String, Sendable {
    case ping = "ping"
    case health = "health"
    case meetingList = "meeting.list"
    case meetingGet = "meeting.get"
    case meetingCreate = "meeting.create"
    case meetingTransition = "meeting.transition"
    case meetingSummaryGet = "meeting.summary.get"
    case meetingReviewAccept = "meeting.review.accept"
    case meetingRetry = "meeting.retry"
    /// UI completed Apple Speech (or other) ASR — force-complete to transcribed.
    case meetingAsrComplete = "meeting.asr.complete"
    /// Abandon stale `recording` rows so a new capture can start.
    case meetingAbandonOrphans = "meeting.abandon_orphans"
}

public struct HealthResult: Codable, Sendable {
    public var ok: Bool
    public var version: String
    public var dbPath: String
    public var recordingCount: Int
    public var reviewNeededCount: Int

    public init(ok: Bool, version: String, dbPath: String, recordingCount: Int, reviewNeededCount: Int) {
        self.ok = ok
        self.version = version
        self.dbPath = dbPath
        self.recordingCount = recordingCount
        self.reviewNeededCount = reviewNeededCount
    }
}

// Bump when daemon capabilities change (pipeline tick, etc.)
public enum DaemonVersion {
    public static let current = "0.3.0-pr07"
}
