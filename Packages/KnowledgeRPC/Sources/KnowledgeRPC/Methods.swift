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
    /// FTS search over derived index (meeting summaries etc.)
    case search = "search"
    /// Rebuild FTS for committed meetings from candidate/vault pointers.
    case searchReindex = "search.reindex"
    /// Sync full knowledge corpus (meetings + connected sources).
    case corpusSync = "corpus.sync"
    case corpusStatus = "corpus.status"
    case meetingDelete = "meeting.delete"
    case meetingPurgeAbandoned = "meeting.purge_abandoned"
}

// Bump when daemon capabilities change (pipeline tick, etc.)
public enum DaemonVersion {
    public static let current = "0.5.0-dogfood"
}
