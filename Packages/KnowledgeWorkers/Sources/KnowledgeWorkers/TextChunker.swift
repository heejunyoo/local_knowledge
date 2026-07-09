import Foundation

/// Structure-aware chunking with overlap — better retrieval unit than fixed windows.
public enum TextChunker {
    public struct Options: Equatable, Sendable {
        public var targetChars: Int
        public var overlapChars: Int
        public var minChars: Int

        public init(targetChars: Int = 800, overlapChars: Int = 120, minChars: Int = 40) {
            self.targetChars = targetChars
            self.overlapChars = overlapChars
            self.minChars = minChars
        }

        public static let `default` = Options()
    }

    /// Split markdown / notes body preferring headers and blank lines.
    public static func chunk(_ text: String, options: Options = .default) -> [String] {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = splitBlocks(cleaned)
        var out: [String] = []
        var buf = ""
        var sectionPrefix = ""

        func flush() {
            let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= options.minChars || (!t.isEmpty && out.isEmpty) else {
                buf = ""
                return
            }
            out.append(t)
            // Overlap tail into next buffer
            if options.overlapChars > 0, t.count > options.overlapChars {
                let start = t.index(t.endIndex, offsetBy: -options.overlapChars)
                buf = String(t[start...])
            } else {
                buf = ""
            }
        }

        for block in blocks {
            let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty else { continue }

            if isHeader(b) {
                flush()
                sectionPrefix = normalizeHeader(b) + "\n"
                buf = sectionPrefix
                continue
            }

            let candidate = buf.isEmpty ? b : buf + "\n\n" + b
            if candidate.count <= options.targetChars {
                buf = candidate
            } else {
                if !buf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flush()
                    // keep section prefix after flush if we had one
                    if !sectionPrefix.isEmpty, !buf.hasPrefix(sectionPrefix) {
                        buf = sectionPrefix + b
                    } else if buf.isEmpty {
                        buf = (sectionPrefix.isEmpty ? "" : sectionPrefix) + b
                    } else {
                        buf = buf + "\n\n" + b
                    }
                    if buf.count > options.targetChars * 2 {
                        // hard split long block
                        for piece in hardSplit(buf, target: options.targetChars, overlap: options.overlapChars) {
                            out.append(piece)
                        }
                        buf = sectionPrefix
                    }
                } else {
                    for piece in hardSplit(b, target: options.targetChars, overlap: options.overlapChars) {
                        let p = sectionPrefix.isEmpty ? piece : sectionPrefix + piece
                        out.append(p)
                    }
                    buf = sectionPrefix
                }
            }
        }
        flush()
        return out.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= options.minChars }
    }

    /// Label meeting structured fields so retrieval can boost them.
    public static func labeledMeetingPieces(
        oneLine: String?,
        discussion: [String],
        decisions: [String],
        actions: [String],
        open: [String]
    ) -> [String] {
        var out: [String] = []
        if let oneLine, !oneLine.isEmpty {
            out.append("[한줄] \(oneLine)")
        }
        for t in discussion where !t.isEmpty { out.append("[논의] \(t)") }
        for t in decisions where !t.isEmpty { out.append("[결정] \(t)") }
        for t in actions where !t.isEmpty { out.append("[할일] \(t)") }
        for t in open where !t.isEmpty { out.append("[이슈] \(t)") }
        return out
    }

    // MARK: - internals

    private static func splitBlocks(_ text: String) -> [String] {
        // Split on blank lines, but keep single newlines inside lists together when possible
        text.components(separatedBy: "\n\n")
    }

    private static func isHeader(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { return true }
        // Common vault section titles
        let known = ["주요 논의", "결정", "할 일", "액션", "미해결", "요약", "Agenda", "Notes"]
        return known.contains(where: { t == $0 || t.hasPrefix($0 + " ") })
    }

    private static func normalizeHeader(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { return t }
        return "## \(t)"
    }

    private static func hardSplit(_ text: String, target: Int, overlap: Int) -> [String] {
        if text.count <= target { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: target, limitedBy: text.endIndex) ?? text.endIndex
            var sliceEnd = end
            if end < text.endIndex {
                let window = text[start..<end]
                if let nl = window.lastIndex(of: "\n") {
                    sliceEnd = text.index(after: nl)
                } else if let sp = window.lastIndex(of: " ") {
                    sliceEnd = text.index(after: sp)
                }
            }
            let piece = String(text[start..<sliceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            if sliceEnd >= text.endIndex { break }
            // step back for overlap
            if overlap > 0 {
                let back = text.index(sliceEnd, offsetBy: -min(overlap, text.distance(from: start, to: sliceEnd)), limitedBy: start) ?? start
                start = back == start ? sliceEnd : back
            } else {
                start = sliceEnd
            }
        }
        return out
    }
}
