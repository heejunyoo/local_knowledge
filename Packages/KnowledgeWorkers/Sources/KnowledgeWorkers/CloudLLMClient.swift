import Foundation

/// HTTP clients for free-tier providers. No SDKs — easy to swap endpoints via catalog.
public enum CloudLLMClient {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var providerId: String
        public var model: String
        public var engine: String

        public init(text: String, providerId: String, model: String) {
            self.text = text
            self.providerId = providerId
            self.model = model
            self.engine = "cloud/\(providerId)/\(model)"
        }
    }

    public enum ClientError: Error, CustomStringConvertible {
        case noKey
        case http(Int, String)
        case empty
        case badURL

        public var description: String {
            switch self {
            case .noKey: return "api key missing"
            case let .http(c, b): return "http \(c): \(b.prefix(180))"
            case .empty: return "empty response"
            case .badURL: return "bad url"
            }
        }
    }

    /// Try one provider (all models in fallback list).
    public static func complete(
        providerId: String,
        def: LLMProviderCatalog.ProviderDef,
        apiKey: String,
        prompt: String,
        maxTokens: Int = 512
    ) throws -> Result {
        var last: Error = ClientError.empty
        for model in def.modelsToTry {
            do {
                let text: String
                switch def.kind {
                case "gemini":
                    text = try geminiGenerate(
                        baseURL: def.baseURL,
                        model: model,
                        apiKey: apiKey,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        timeout: def.timeoutSec
                    )
                case "openai_compatible":
                    text = try openaiChat(
                        baseURL: def.baseURL,
                        model: model,
                        apiKey: apiKey,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        timeout: def.timeoutSec,
                        extraHeaders: def.extraHeaders
                    )
                default:
                    throw ClientError.badURL
                }
                let cleaned = clean(text)
                guard !cleaned.isEmpty else { throw ClientError.empty }
                return Result(text: cleaned, providerId: providerId, model: model)
            } catch {
                last = error
                continue
            }
        }
        throw last
    }

    // MARK: - Gemini generateContent (stable free-tier path)

    private static func geminiGenerate(
        baseURL: String,
        model: String,
        apiKey: String,
        prompt: String,
        maxTokens: Int,
        timeout: TimeInterval
    ) throws -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: "\(base)/models/\(model):generateContent") else {
            throw ClientError.badURL
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw ClientError.badURL }

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]],
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": maxTokens,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (respData, resp) = try syncRequest(req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw ClientError.http(code, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let cands = obj["candidates"] as? [[String: Any]],
              let first = cands.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ClientError.empty
        }
        let texts = parts.compactMap { $0["text"] as? String }
        let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty { throw ClientError.empty }
        return joined
    }

    // MARK: - OpenAI-compatible (Groq, OpenRouter, future free tiers)

    private static func openaiChat(
        baseURL: String,
        model: String,
        apiKey: String,
        prompt: String,
        maxTokens: Int,
        timeout: TimeInterval,
        extraHeaders: [String: String]
    ) throws -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else { throw ClientError.badURL }

        // System message improves Korean grounded answers (RAG / coach) on free models.
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    당신은 로컬 개인 비서입니다. 사용자가 준 근거·질문만으로 한국어로 명확히 답하세요.
                    근거에 없으면 모른다고 말하세요. 추측·장황한 서론 금지. 2~6문장 또는 짧은 불릿.
                    내부 사고 과정·태그(<think> 등)는 출력하지 마세요.
                    """,
                ],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.2,
            "max_tokens": maxTokens,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = data

        let (respData, resp) = try syncRequest(req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw ClientError.http(code, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClientError.empty
        }
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { throw ClientError.empty }
        return t
    }

    private static func syncRequest(_ req: URLRequest) throws -> (Data, URLResponse) {
        let sem = DispatchSemaphore(value: 0)
        var outData: Data?
        var outResp: URLResponse?
        var outErr: Error?
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            outData = data
            outResp = resp
            outErr = err
            sem.signal()
        }
        task.resume()
        let wait = sem.wait(timeout: .now() + (req.timeoutInterval + 5))
        if wait == .timedOut {
            task.cancel()
            throw ClientError.http(408, "timeout")
        }
        if let outErr { throw outErr }
        guard let outData, let outResp else { throw ClientError.empty }
        return (outData, outResp)
    }

    private static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip Qwen-style chain-of-thought leakage if a model still emits it.
        if let start = s.range(of: "<think>"), let end = s.range(of: "</think>") {
            s.removeSubrange(start.lowerBound...end.upperBound)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let start = s.range(of: "<think>") {
            // unclosed think block — drop everything before last plausible answer line
            s = String(s[start.upperBound...])
            if let end = s.range(of: "</think>") {
                s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let r = s.range(of: "### 답변") {
            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.count > 2000 { s = String(s.prefix(2000)) + "…" }
        return s
    }
}
