import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Local retrieve-then-answer over knowledge_chunk / FTS (no cloud dump).
/// Retrieval v2: LocalRetrieve (BM25 + structure + neighbor + MMR) then generate.
public enum KnowledgeRAG {
    public struct Citation: Equatable, Sendable, Identifiable {
        public var id: String { "\(unitId)#\(ordinal)" }
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

    public struct Answer: Equatable, Sendable {
        public var question: String
        public var answer: String
        public var citations: [Citation]
        public var engine: String

        public init(question: String, answer: String, citations: [Citation], engine: String) {
            self.question = question
            self.answer = answer
            self.citations = citations
            self.engine = engine
        }
    }

    /// Fast path: retrieve + extractive only (UI shows this immediately).
    public static func askFast(
        question: String,
        store: KnowledgeStore,
        topK: Int = 8
    ) throws -> Answer {
        try ask(question: question, store: store, knowledgeRoot: nil, topK: topK, useLlama: false)
    }

    /// Optional LLM refine over an existing extractive answer (cloud first, then 7B short).
    public static func refine(
        question: String,
        citations: [Citation],
        knowledgeRoot: URL,
        useLlama: Bool = true
    ) -> Answer? {
        guard !citations.isEmpty else { return nil }
        // Fewer / shorter contexts → much faster local 7B
        let ctx = citations.prefix(3).map { c -> (String, String) in
            let snip = c.snippet.count > 220 ? String(c.snippet.prefix(220)) + "…" : c.snippet
            return (c.title, snip)
        }
        let prompt = LocalLLM.ragPrompt(question: question, contexts: ctx)
        // Slightly longer for readable mobile/desktop answers; cloud-first.
        if let gen = LLMRouter.complete(
            prompt: prompt,
            knowledgeRoot: knowledgeRoot,
            maxTokens: 420,
            preferCloud: true,
            preferLocal7B: useLlama,
            localTimeout: 40
        ), isPlausibleAnswer(gen.text) {
            var text = gen.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // P0-3 trust gate: always surface source titles when we had retrieval hits.
            text = appendCitationFooterIfNeeded(answer: text, citations: citations)
            return Answer(
                question: question,
                answer: text,
                citations: citations,
                engine: "\(gen.engine)+retrieve-v2"
            )
        }
        return nil
    }

    /// Ensure refined answers still show human-readable grounds (W0 G-Trust).
    private static func appendCitationFooterIfNeeded(answer: String, citations: [Citation]) -> String {
        let titles = citations.prefix(3).map(\.title).filter { !$0.isEmpty }
        guard !titles.isEmpty else { return answer }
        let lower = answer.lowercased()
        if answer.contains("근거") || answer.contains("출처") || lower.contains("source") {
            return answer
        }
        let line = "근거: " + titles.map { "「\($0)」" }.joined(separator: ", ")
        return answer + "\n\n" + line
    }

    public static func ask(
        question: String,
        store: KnowledgeStore,
        knowledgeRoot: URL? = nil,
        topK: Int = 8,
        useLlama: Bool = true
    ) throws -> Answer {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return Answer(
                question: question,
                answer: "질문을 입력해 주세요.",
                citations: [],
                engine: "extractive-rag/v1"
            )
        }

        let hits = try LocalRetrieve.retrieve(query: q, store: store, topK: topK)
        let citations = hits.map {
            Citation(
                unitId: $0.unitId,
                title: $0.title,
                sourceType: $0.sourceType,
                snippet: $0.snippet,
                ordinal: $0.ordinal,
                tStartMs: $0.tStartMs,
                tEndMs: $0.tEndMs,
                score: $0.score
            )
        }

        if citations.isEmpty {
            return Answer(
                question: q,
                answer: """
                모은 지식에서 관련 내용을 찾지 못했어요.

                · 미팅을 저장했는지
                · 지식 연결에서 동기화했는지
                를 확인해 주세요.
                """,
                citations: [],
                engine: "retrieve-v2"
            )
        }

        // Blocking full path (tests / dogfood): try LLM then extractive
        if let root = knowledgeRoot {
            if let refined = refine(
                question: q,
                citations: citations,
                knowledgeRoot: root,
                useLlama: useLlama
            ) {
                return refined
            }
        }

        let answer = synthesize(question: q, citations: citations)
        return Answer(question: q, answer: answer, citations: citations, engine: "extractive-rag/v2")
    }

    // MARK: - Natural extractive answer

    private static func synthesize(question: String, citations: [Citation]) -> String {
        struct Bullet {
            var kind: String
            var title: String
            var text: String
        }
        let tops = Array(citations.prefix(5))
        let bullets: [Bullet] = tops.map { c in
            Bullet(kind: label(for: c.sourceType), title: c.title, text: cleanSnippet(c.snippet))
        }

        var parts: [String] = []
        if let best = bullets.first {
            let lead = compressSentence(best.text, max: 180)
            if looksLikeDirectAnswer(question: question, text: lead) {
                parts.append(lead)
            } else {
                parts.append("「\(best.title)」 기준으로 보면, \(decapitalizeIfNeeded(lead))")
            }
        }

        var used = Set(parts.map { normalizeKey($0) })
        var supports: [String] = []
        for b in bullets.dropFirst() {
            let line = compressSentence(b.text, max: 140)
            let key = normalizeKey(line)
            guard !key.isEmpty, !used.contains(key) else { continue }
            if used.contains(where: { jaccard($0, key) > 0.55 }) { continue }
            used.insert(key)
            supports.append("· \(line) (\(b.kind) · \(b.title))")
            if supports.count >= 3 { break }
        }
        if !supports.isEmpty {
            parts.append("")
            parts.append(contentsOf: supports)
        }

        let sourceCount = Set(tops.map(\.unitId)).count
        parts.append("")
        parts.append("근거 \(sourceCount)개 출처 · 아래 카드를 누르면 원문으로 이동해요.")
        return parts.joined(separator: "\n")
    }

    private static func isPlausibleAnswer(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 12, t.count <= 1600 else { return false }
        if t.contains("### 근거") || t.contains("### 질문") { return false }
        if t.lowercased().contains("as an ai") { return false }
        if t.contains("<think>") || t.contains("</think>") { return false }
        return true
    }

    private static func cleanSnippet(_ s: String) -> String {
        var t = s
            .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") || t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix("[") {
            if t.hasPrefix("["), let r = t.range(of: "]") {
                t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                continue
            }
            t = String(t.drop(while: { "#-* ".contains($0) }))
        }
        return t
    }

    private static func compressSentence(_ s: String, max: Int) -> String {
        var t = cleanSnippet(s)
        let seps = CharacterSet(charactersIn: ".。!?？")
        if let r = t.rangeOfCharacter(from: seps) {
            let first = String(t[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
            if first.count >= 20 {
                t = first
                let rest = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if first.count < 80, let r2 = rest.rangeOfCharacter(from: seps) {
                    let second = String(rest[..<r2.upperBound]).trimmingCharacters(in: .whitespaces)
                    if !second.isEmpty { t = first + " " + second }
                }
            }
        }
        if t.count > max { t = String(t.prefix(max - 1)) + "…" }
        return t
    }

    private static func looksLikeDirectAnswer(question: String, text: String) -> Bool {
        let toks = QueryTerms.expand(question).filter { $0.count >= 2 }
        guard !toks.isEmpty else { return text.count >= 30 }
        let lower = text.lowercased()
        let hit = toks.filter { lower.contains($0.lowercased()) }.count
        return Double(hit) / Double(toks.count) >= 0.25
    }

    private static func decapitalizeIfNeeded(_ s: String) -> String {
        guard let first = s.first else { return s }
        if first.isASCII && first.isUppercase {
            return first.lowercased() + s.dropFirst()
        }
        return s
    }

    private static func normalizeKey(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .prefix(80)
            .description
    }

    private static func jaccard(_ a: String, _ b: String) -> Double {
        let sa = Set(a.map(String.init))
        let sb = Set(b.map(String.init))
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }

    private static func label(for sourceType: String) -> String {
        switch sourceType {
        case "meeting": return "미팅"
        case "notes": return "Notes"
        case "obsidian": return "Obsidian"
        case "file": return "파일"
        default: return sourceType
        }
    }
}
