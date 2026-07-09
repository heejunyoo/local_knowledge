import Foundation

/// Merge ASR word-level crumbs into phrase/sentence segments for summarization.
public enum TranscriptCoalesce {
    /// Gap (ms) larger than this starts a new segment.
    public static let maxGapMs: Int = 700
    /// Soft max characters per merged segment (Korean ~one short sentence).
    public static let maxChars: Int = 80
    /// Soft max duration per merged segment.
    public static let maxDurationMs: Int = 12_000

    public static func coalesce(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }

        // Already phrase-sized? keep as-is.
        let avgLen = segments.map(\.text.count).reduce(0, +) / max(segments.count, 1)
        if segments.count <= 8 || avgLen >= 12 {
            return renumber(segments)
        }

        var out: [TranscriptSegment] = []
        var bufText = ""
        var bufStart = segments[0].tStartMs
        var bufEnd = segments[0].tEndMs
        var lastEnd = segments[0].tEndMs

        func flush() {
            let t = bufText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            out.append(TranscriptSegment(
                index: out.count,
                tStartMs: bufStart,
                tEndMs: max(bufEnd, bufStart + 1),
                text: t
            ))
            bufText = ""
        }

        for (i, seg) in segments.enumerated() {
            let piece = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            if bufText.isEmpty {
                bufText = piece
                bufStart = seg.tStartMs
                bufEnd = seg.tEndMs
                lastEnd = seg.tEndMs
                continue
            }

            let gap = seg.tStartMs - lastEnd
            let would = joinKorean(bufText, piece)
            let dur = seg.tEndMs - bufStart
            let shouldBreak =
                gap > maxGapMs
                || would.count > maxChars
                || dur > maxDurationMs
                || endsSentence(bufText)

            if shouldBreak {
                flush()
                bufText = piece
                bufStart = seg.tStartMs
                bufEnd = seg.tEndMs
            } else {
                bufText = would
                bufEnd = seg.tEndMs
            }
            lastEnd = seg.tEndMs

            if i == segments.count - 1 {
                flush()
            }
        }
        if !bufText.isEmpty { flush() }
        return out.isEmpty ? renumber(segments) : out
    }

    public static func apply(to doc: TranscriptDocument) -> TranscriptDocument {
        var copy = doc
        copy.segments = coalesce(doc.segments)
        return copy
    }

    public static func fullText(_ segments: [TranscriptSegment]) -> String {
        segments.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renumber(_ segs: [TranscriptSegment]) -> [TranscriptSegment] {
        segs.enumerated().map { i, s in
            TranscriptSegment(index: i, tStartMs: s.tStartMs, tEndMs: s.tEndMs, text: s.text)
        }
    }

    private static func joinKorean(_ a: String, _ b: String) -> String {
        // Hangul/CJK: no space; Latin/digits: space
        let last = a.unicodeScalars.last
        let first = b.unicodeScalars.first
        let needsSpace: Bool = {
            guard let last, let first else { return true }
            let hangul = CharacterSet(charactersIn: "\u{AC00}"..."\u{D7A3}")
            let cjk = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
            if hangul.contains(last) || cjk.contains(last) { return false }
            if hangul.contains(first) || cjk.contains(first) { return false }
            return true
        }()
        return needsSpace ? "\(a) \(b)" : "\(a)\(b)"
    }

    private static func endsSentence(_ s: String) -> Bool {
        guard let c = s.last else { return false }
        return ".!?。！？…".contains(c)
    }
}
