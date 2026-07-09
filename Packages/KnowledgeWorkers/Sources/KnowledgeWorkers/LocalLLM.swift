import Foundation
import KnowledgeCore

/// Optional llama.cpp completion for RAG v2. Missing tools → nil (caller degrades).
public enum LocalLLM {
    public static func isAvailable(knowledgeRoot: URL) -> Bool {
        let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
        return ((try? boot.llamaBinaryURL()) != nil) && ((try? boot.llamaModelURL()) != nil)
    }

    /// Short grounded answer. Returns nil if tools missing or worker fails.
    /// Tuned for chat latency on M4 16GB: Metal offload, small context, low n.
    public static func complete(
        prompt: String,
        knowledgeRoot: URL,
        maxTokens: Int = 160,
        timeout: TimeInterval = 45
    ) throws -> String? {
        let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
        guard let binary = try boot.llamaBinaryURL(),
              let model = try boot.llamaModelURL() else {
            return nil
        }

        // Metal GPU layers + compact context. Fallbacks for older flag sets.
        let attempts: [[String]] = [
            [
                "-m", model.path,
                "-n", "\(maxTokens)",
                "-c", "2048",
                "-ngl", "99",
                "--temp", "0.2",
                "--top-p", "0.9",
                "-no-cnv",
                "--simple-io",
                "-p", prompt,
            ],
            [
                "-m", model.path,
                "-n", "\(maxTokens)",
                "-c", "2048",
                "--temp", "0.2",
                "-no-cnv",
                "-p", prompt,
            ],
            [
                "-m", model.path,
                "-n", "\(maxTokens)",
                "--temp", "0.2",
                "-p", prompt,
            ],
        ]

        for args in attempts {
            let result = try WorkerProcess.run(
                executable: binary,
                arguments: args,
                timeout: timeout
            )
            if result.timedOut { continue }
            if let text = extractText(result), !text.isEmpty {
                return clean(text)
            }
        }
        return nil
    }

    /// Optional polish for meeting one-line after extractive (best-effort).
    public static func polishOneLine(
        draft: String,
        knowledgeRoot: URL
    ) throws -> String? {
        guard isAvailable(knowledgeRoot: knowledgeRoot) else { return nil }
        let prompt = """
        다음 회의 한 줄 요약을 한국어로 더 자연스럽게 다듬으세요.
        사실 추가 금지. 40자 이내. 설명 없이 결과만.

        원문: \(draft)

        한 줄:
        """
        guard let out = try complete(prompt: prompt, knowledgeRoot: knowledgeRoot, maxTokens: 80, timeout: 40)
        else { return nil }
        let line = out
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? out
        if line.count < 4 || line.count > 120 { return nil }
        return line
    }

    public static func ragPrompt(question: String, contexts: [(title: String, snippet: String)]) -> String {
        var ctx = ""
        for (i, c) in contexts.enumerated() {
            ctx += "[\(i + 1)] \(c.title)\n\(c.snippet)\n\n"
        }
        return """
        당신은 개인 지식 비서입니다. 아래 근거만 사용해 한국어로 짧게 답하세요.
        근거에 없으면 "모은 지식에서 찾지 못했어요"라고 말하세요.
        추측하지 마세요. 2~5문장. 불릿이 필요하면 · 사용.

        ### 근거
        \(ctx)
        ### 질문
        \(question)

        ### 답변
        """
    }

    private static func extractText(_ result: WorkerResult) -> String? {
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty && (result.succeeded || result.exitCode == 0) {
            return out
        }
        // Some builds dump completion to stderr
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty && result.exitCode == 0 {
            return err
        }
        if !out.isEmpty { return out }
        return nil
    }

    private static func clean(_ raw: String) -> String {
        var s = raw
        // Drop echoed prompt tails if present
        if let r = s.range(of: "### 답변") {
            s = String(s[r.upperBound...])
        }
        if let r = s.range(of: "한 줄:") {
            s = String(s[r.upperBound...])
        }
        // Drop llama.cpp log lines
        let lines = s.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.hasPrefix("llama_") { return false }
            if t.hasPrefix("ggml_") { return false }
            if t.hasPrefix("main:") { return false }
            if t.hasPrefix("system_info:") { return false }
            if t.hasPrefix("sampling:") { return false }
            if t.hasPrefix("generate:") { return false }
            if t.hasPrefix("load_") { return false }
            if t.contains("tokens per second") { return false }
            return true
        }
        s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 1200 { s = String(s.prefix(1200)) + "…" }
        return s
    }
}
