import Foundation
import KnowledgeIndex

/// Improved local retrieval for PKM RAG (2026-07 Field v2).
/// BM25 over candidate pool + structure boost + neighbor expansion + MMR diversity.
/// No embeddings yet — still purely local, makes 7B generation useful.
public enum LocalRetrieve {
    public struct Hit: Equatable, Sendable {
        public var unitId: String
        public var title: String
        public var sourceType: String
        public var snippet: String
        public var ordinal: Int
        public var tStartMs: Int?
        public var tEndMs: Int?
        public var score: Double

        public init(
            unitId: String,
            title: String,
            sourceType: String,
            snippet: String,
            ordinal: Int,
            tStartMs: Int? = nil,
            tEndMs: Int? = nil,
            score: Double
        ) {
            self.unitId = unitId
            self.title = title
            self.sourceType = sourceType
            self.snippet = snippet
            self.ordinal = ordinal
            self.tStartMs = tStartMs
            self.tEndMs = tEndMs
            self.score = score
        }
    }

    public static func retrieve(
        query: String,
        store: KnowledgeStore,
        topK: Int = 8
    ) throws -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let terms = QueryTerms.expand(q)
        guard !terms.isEmpty else { return [] }

        // 1) Candidate gather (multi-term LIKE + FTS units)
        var pool: [String: (chunk: KnowledgeChunkRecord, title: String)] = [:]

        // Full query
        for (chunk, title) in try store.searchChunks(query: q, limit: topK * 4) {
            pool[chunk.chunkId] = (chunk, title ?? chunk.unitId)
        }
        // Per-term (Korean multi-keyword)
        for term in terms.prefix(12) where term.count >= 2 {
            for (chunk, title) in try store.searchChunks(query: term, limit: 16) {
                if pool[chunk.chunkId] == nil {
                    pool[chunk.chunkId] = (chunk, title ?? chunk.unitId)
                }
            }
        }
        // FTS unit → all matching chunks for those units
        let fts = try store.searchFTS(query: q, limit: topK * 2)
        for hit in fts {
            for (chunk, title) in try store.searchChunks(query: q, limit: 30)
                .filter({ $0.chunk.unitId == hit.docId }) {
                pool[chunk.chunkId] = (chunk, title ?? hit.title ?? chunk.unitId)
            }
            // Also term hits within unit via title search of terms
            for term in terms.prefix(6) {
                for (chunk, title) in try store.searchChunks(query: term, limit: 12)
                    .filter({ $0.chunk.unitId == hit.docId }) {
                    if pool[chunk.chunkId] == nil {
                        pool[chunk.chunkId] = (chunk, title ?? hit.title ?? chunk.unitId)
                    }
                }
            }
        }

        if pool.isEmpty { return [] }

        let candidates = Array(pool.values)
        let docs = candidates.map(\.chunk.text)
        let avgdl = docs.map { Double($0.count) }.reduce(0, +) / Double(max(1, docs.count))
        let df = documentFrequencies(terms: terms, docs: docs)

        // 2) Score
        var scored: [Hit] = []
        for (chunk, title) in candidates {
            let bm = bm25(terms: terms, doc: chunk.text, df: df, nDocs: docs.count, avgdl: avgdl)
            let structural = structureBoost(chunk.text)
            let exact = chunk.text.localizedCaseInsensitiveContains(q) ? 1.2 : 0
            let titleBoost = title.localizedCaseInsensitiveContains(q) ? 0.4 : 0
            let meetingBoost = chunk.unitId.hasPrefix("meeting:") && structural > 0 ? 0.3 : 0
            let score = bm + structural + exact + titleBoost + meetingBoost
            guard score > 0.05 else { continue }
            scored.append(Hit(
                unitId: chunk.unitId,
                title: title,
                sourceType: sourceType(from: chunk.unitId),
                snippet: clip(chunk.text, max: 400),
                ordinal: chunk.ordinal,
                tStartMs: chunk.tStartMs,
                tEndMs: chunk.tEndMs,
                score: score
            ))
        }

        // 2b) Hybrid vector boost (hash embeddings when present)
        let qVec = LocalHashEmbedder.embed(q)
        if let vectors = try? store.allChunkVectors(limit: 4000), !vectors.isEmpty {
            var byId: [String: Float] = [:]
            for row in vectors {
                byId[row.chunkId] = LocalHashEmbedder.cosine(qVec, row.vec)
            }
            for i in scored.indices {
                let key = "\(scored[i].unitId)#\(scored[i].ordinal)"
                // chunk_id format
                let cid = "\(scored[i].unitId)#\(scored[i].ordinal)"
                if let cos = byId[cid] ?? byId[key] {
                    scored[i].score += Double(cos) * 2.2
                }
            }
            // Also add pure-vector hits not in lexical pool
            let rankedVec = vectors
                .map { ($0, LocalHashEmbedder.cosine(qVec, $0.vec)) }
                .sorted { $0.1 > $1.1 }
                .prefix(topK * 2)
            for (row, cos) in rankedVec where cos > 0.08 {
                let exists = scored.contains { $0.unitId == row.unitId && $0.ordinal == row.ordinal }
                if exists { continue }
                scored.append(Hit(
                    unitId: row.unitId,
                    title: row.title,
                    sourceType: sourceType(from: row.unitId),
                    snippet: clip(row.text, max: 400),
                    ordinal: row.ordinal,
                    score: Double(cos) * 2.5 + structureBoost(row.text)
                ))
            }
        }

        scored.sort { $0.score > $1.score }

        // 3) Neighbor expansion for top units
        var expanded = scored
        for hit in scored.prefix(topK) {
            let neighbors = try store.chunks(forUnit: hit.unitId)
            for ch in neighbors where abs(ch.ordinal - hit.ordinal) == 1 {
                let keyExists = expanded.contains { $0.unitId == ch.unitId && $0.ordinal == ch.ordinal }
                if keyExists { continue }
                let nbScore = hit.score * 0.55 + structureBoost(ch.text) * 0.5
                expanded.append(Hit(
                    unitId: ch.unitId,
                    title: hit.title,
                    sourceType: hit.sourceType,
                    snippet: clip(ch.text, max: 400),
                    ordinal: ch.ordinal,
                    tStartMs: ch.tStartMs,
                    tEndMs: ch.tEndMs,
                    score: nbScore
                ))
            }
        }
        expanded.sort { $0.score > $1.score }

        // 4) MMR diversity (avoid 8 chunks from same note)
        return mmr(hits: expanded, topK: topK, lambda: 0.72)
    }

    // MARK: - BM25 / terms

    private static func bm25(
        terms: [String],
        doc: String,
        df: [String: Int],
        nDocs: Int,
        avgdl: Double,
        k1: Double = 1.4,
        b: Double = 0.75
    ) -> Double {
        let lower = doc.lowercased()
        let dl = Double(max(1, doc.count))
        var score = 0.0
        for term in terms {
            let t = term.lowercased()
            guard !t.isEmpty else { continue }
            let tf = Double(countOccurrences(of: t, in: lower))
            guard tf > 0 else { continue }
            let dfi = Double(df[t] ?? 1)
            let idf = log((Double(nDocs) - dfi + 0.5) / (dfi + 0.5) + 1.0)
            let denom = tf + k1 * (1.0 - b + b * dl / max(avgdl, 1))
            score += idf * (tf * (k1 + 1.0)) / denom
        }
        return score
    }

    private static func documentFrequencies(terms: [String], docs: [String]) -> [String: Int] {
        var df: [String: Int] = [:]
        for term in terms {
            let t = term.lowercased()
            var c = 0
            for d in docs where d.lowercased().contains(t) { c += 1 }
            df[t] = max(1, c)
        }
        return df
    }

    private static func countOccurrences(of needle: String, in hay: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = hay.startIndex
        while search < hay.endIndex,
              let r = hay.range(of: needle, options: .caseInsensitive, range: search..<hay.endIndex) {
            count += 1
            search = r.upperBound
        }
        return count
    }

    /// Boost structured PKM / meeting labels and markdown headers.
    public static func structureBoost(_ text: String) -> Double {
        var s = 0.0
        let t = text
        if t.contains("[결정]") || t.contains("## 결정") { s += 1.1 }
        if t.contains("[할일]") || t.contains("할 일") || t.contains("## 할") { s += 1.0 }
        if t.contains("[한줄]") || t.contains("one_line") { s += 0.6 }
        if t.contains("[논의]") || t.contains("주요 논의") { s += 0.5 }
        if t.contains("[이슈]") || t.contains("미해결") { s += 0.5 }
        if t.hasPrefix("#") || t.contains("\n## ") { s += 0.25 }
        return s
    }

    private static func mmr(hits: [Hit], topK: Int, lambda: Double) -> [Hit] {
        guard !hits.isEmpty else { return [] }
        var selected: [Hit] = []
        var rest = hits
        while selected.count < topK, !rest.isEmpty {
            var bestIdx = 0
            var bestScore = -Double.infinity
            for (i, h) in rest.enumerated() {
                let mmr: Double
                if selected.isEmpty {
                    mmr = h.score
                } else {
                    let sim = selected.map { jaccard($0.snippet, h.snippet) }.max() ?? 0
                    let sameUnit = selected.contains(where: { $0.unitId == h.unitId }) ? 0.25 : 0
                    mmr = lambda * h.score - (1 - lambda) * (sim * 2 + sameUnit)
                }
                if mmr > bestScore {
                    bestScore = mmr
                    bestIdx = i
                }
            }
            selected.append(rest.remove(at: bestIdx))
        }
        return selected
    }

    private static func jaccard(_ a: String, _ b: String) -> Double {
        let sa = Set(QueryTerms.tokens(a))
        let sb = Set(QueryTerms.tokens(b))
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }

    private static func sourceType(from unitId: String) -> String {
        if unitId.hasPrefix("meeting:") { return "meeting" }
        if unitId.hasPrefix("notes:") { return "notes" }
        if unitId.hasPrefix("obsidian:") { return "obsidian" }
        if unitId.hasPrefix("file:") { return "file" }
        return "unknown"
    }

    private static func clip(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        return String(t.prefix(max)) + "…"
    }
}

/// Query tokenization + expansion for Korean/English PKM queries.
public enum QueryTerms {
    public static func expand(_ query: String) -> [String] {
        var terms = tokens(query)
        // Always Hangul bigrams / trigrams for continuous Korean
        let compact = query.replacingOccurrences(of: " ", with: "")
        let chars = Array(compact)
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                let bi = String(chars[i...i + 1])
                if isHangul(bi) { terms.append(bi) }
            }
        }
        if chars.count >= 3 {
            for i in 0..<(chars.count - 2) {
                let tri = String(chars[i...i + 2])
                if isHangul(tri) { terms.append(tri) }
            }
        }
        // Drop stop-ish short noise
        let stop: Set<String> = ["은", "는", "이", "가", "을", "를", "의", "에", "와", "과", "도", "로", "으로", "뭐", "무엇", "어디", "언제", "how", "what", "the", "a"]
        terms = terms.filter { $0.count >= 2 && !stop.contains($0.lowercased()) }
        return Array(Set(terms)).sorted()
    }

    public static func tokens(_ q: String) -> [String] {
        q.split { $0.isWhitespace || "?,.!;:\"'()[]【】「」".contains($0) }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func isHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
    }
}
