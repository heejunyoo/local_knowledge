import Foundation

/// Minimal Core gateway client (M1–M3).
@MainActor
public final class CoreClient: ObservableObject {
    @Published public var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "core.baseURL") }
    }
    @Published public var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "core.token") }
    }
    @Published public var deviceId: String {
        didSet { UserDefaults.standard.set(deviceId, forKey: "core.deviceId") }
    }
    @Published public var coreName: String = ""
    @Published public var lastError: String?
    @Published public var connected: Bool = false
    @Published public var reviewCount: Int = 0
    @Published public var dietLine: String = ""

    public init() {
        self.baseURL = UserDefaults.standard.string(forKey: "core.baseURL") ?? "http://100.x.y.z:8741"
        self.token = UserDefaults.standard.string(forKey: "core.token") ?? ""
        self.deviceId = UserDefaults.standard.string(forKey: "core.deviceId") ?? ""
    }

    public var isPaired: Bool { !token.isEmpty }

    // MARK: - Pairing

    public func completePair(code: String, deviceName: String) async {
        lastError = nil
        // Normalize URL before first request (ensure http://)
        baseURL = normalizedBase()
        do {
            let body: [String: Any] = ["code": code, "device_name": deviceName]
            let res = try await postJSON(path: "/v1/pair/complete", body: body, auth: false)
            if let t = res["token"] as? String {
                token = t
                deviceId = res["device_id"] as? String ?? ""
                coreName = res["core_name"] as? String ?? ""
                connected = true
                lastError = nil
            } else {
                lastError = res["error"] as? String ?? "pair failed"
            }
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("App Transport Security")
                || msg.localizedCaseInsensitiveContains("secure connection") {
                lastError = "보안 정책 오류가 남아 있으면 앱을 삭제 후 Xcode에서 다시 설치하세요. (\(msg))"
            } else {
                lastError = msg
            }
        }
    }

    public func refreshStatus() async {
        guard isPaired else { connected = false; return }
        do {
            let res = try await getJSON(path: "/v1/pair/status", auth: true)
            connected = (res["ok"] as? Bool) ?? false
            coreName = res["core_name"] as? String ?? coreName
            if let err = res["error"] as? String { lastError = err; connected = false }
        } catch {
            connected = false
            lastError = error.localizedDescription
        }
        await refreshReviewCount()
        await refreshDietLine()
    }

    public func revokeRemote() async {
        lastError = nil
        if isPaired {
            _ = try? await postJSON(path: "/v1/pair/revoke", body: [:], auth: true)
        }
        token = ""
        deviceId = ""
        connected = false
        reviewCount = 0
        coreName = ""
    }

    // MARK: - API

    public func search(q: String) async throws -> [[String: Any]] {
        let rpc = try await rpc(method: "knowledge.search", params: ["q": q, "limit": 20])
        if let err = rpc["error"] as? [String: Any] {
            throw NSError(domain: "core", code: 1, userInfo: [NSLocalizedDescriptionKey: err["message"] as? String ?? "error"])
        }
        // result may be {hits:[]} or array depending on daemon
        if let result = rpc["result"] as? [String: Any] {
            if let hits = result["hits"] as? [[String: Any]] { return hits }
            if let items = result["items"] as? [[String: Any]] { return items }
            if let docs = result["results"] as? [[String: Any]] { return docs }
        }
        if let arr = rpc["result"] as? [[String: Any]] { return arr }
        return []
    }

    public func askFast(q: String) async throws -> (answer: String, engine: String, citations: [[String: Any]]) {
        let rpc = try await rpc(method: "knowledge.ask.fast", params: ["q": q, "limit": 8])
        if let err = rpc["error"] as? [String: Any] {
            throw NSError(domain: "core", code: 1, userInfo: [NSLocalizedDescriptionKey: err["message"] as? String ?? "error"])
        }
        let result = rpc["result"] as? [String: Any] ?? [:]
        return (
            result["answer"] as? String ?? "",
            result["engine"] as? String ?? "",
            result["citations"] as? [[String: Any]] ?? []
        )
    }

    public func chat(message: String) async throws -> (answer: String, engine: String, sources: [[String: Any]]) {
        let res = try await postJSON(path: "/v1/chat", body: ["message": message, "mode": "auto"], auth: true)
        if let err = res["error"] as? String {
            throw NSError(domain: "core", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return (
            res["answer"] as? String ?? "",
            res["engine"] as? String ?? "",
            res["sources"] as? [[String: Any]] ?? []
        )
    }

    public func reviewList() async throws -> [[String: Any]] {
        let rpc = try await rpc(method: "knowledge.review.list", params: [:])
        if let err = rpc["error"] as? [String: Any] {
            throw NSError(domain: "core", code: 1, userInfo: [NSLocalizedDescriptionKey: err["message"] as? String ?? "error"])
        }
        if let arr = rpc["result"] as? [[String: Any]] { return arr }
        if let result = rpc["result"] as? [String: Any] {
            if let arr = result["meetings"] as? [[String: Any]] { return arr }
            if let arr = result["items"] as? [[String: Any]] { return arr }
        }
        return []
    }

    public func reviewAccept(id: String) async throws {
        let rpc = try await rpc(method: "knowledge.review.accept", params: ["id": id])
        if let err = rpc["error"] as? [String: Any] {
            throw NSError(domain: "core", code: 1, userInfo: [NSLocalizedDescriptionKey: err["message"] as? String ?? "error"])
        }
    }

    public func refreshReviewCount() async {
        guard isPaired else { reviewCount = 0; return }
        let list = (try? await reviewList()) ?? []
        reviewCount = list.count
    }

    public func dietDaySummary() async throws -> [String: Any] {
        try await dietRPC("diet.day_summary", params: [:])
    }

    public func dietDashboard() async throws -> [String: Any] {
        try await dietRPC("diet.dashboard", params: [:])
    }

    public func dietLogMeal(items: [String], kcal: Double?, proteinG: Double?, note: String?) async throws {
        var p: [String: Any] = ["items": items]
        if let kcal { p["kcal"] = kcal }
        if let proteinG { p["protein_g"] = proteinG }
        if let note { p["note"] = note }
        _ = try await dietRPC("diet.log_meal", params: p)
    }

    public func dietLogWorkout(kind: String, minutes: Int, intensity: String?) async throws {
        var p: [String: Any] = ["kind": kind, "minutes": minutes]
        if let intensity { p["intensity"] = intensity }
        _ = try await dietRPC("diet.log_workout", params: p)
    }

    public func dietLogMetric(weightKg: Double?, sleepH: Double?) async throws {
        var p: [String: Any] = [:]
        if let weightKg { p["weight_kg"] = weightKg }
        if let sleepH { p["sleep_h"] = sleepH }
        _ = try await dietRPC("diet.log_metric", params: p)
    }

    public func dietSetGoals(kcal: Double, protein: Double, weeklyWorkouts: Int, dayMinutes: Int) async throws {
        _ = try await dietRPC("diet.goals.set", params: [
            "target_kcal": kcal,
            "target_protein_g": protein,
            "weekly_workouts": weeklyWorkouts,
            "target_workout_minutes_per_day": dayMinutes,
        ])
    }

    private func dietRPC(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let rpc = try await rpc(method: method, params: params)
        if let err = rpc["error"] as? [String: Any] {
            throw NSError(domain: "core", code: 1, userInfo: [NSLocalizedDescriptionKey: err["message"] as? String ?? "error"])
        }
        return rpc["result"] as? [String: Any] ?? [:]
    }

    public func refreshDietLine() async {
        guard isPaired else { dietLine = ""; return }
        if let dash = try? await dietDashboard(),
           let day = dash["day"] as? [String: Any],
           let text = day["summary_text"] as? String {
            dietLine = text
            return
        }
        guard let day = try? await dietDaySummary() else {
            dietLine = ""
            return
        }
        dietLine = day["summary_text"] as? String ?? ""
    }

    // MARK: - transport

    private func rpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await postJSON(path: "/v1/rpc", body: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ], auth: true)
    }

    private func normalizedBase() -> String {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        // Users sometimes paste without scheme
        if !b.lowercased().hasPrefix("http://"), !b.lowercased().hasPrefix("https://") {
            b = "http://\(b)"
        }
        return b
    }

    private func getJSON(path: String, auth: Bool) async throws -> [String: Any] {
        guard let url = URL(string: normalizedBase() + path) else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = ["Accept": "application/json"]
        if auth, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        // NWConnection cleartext — bypasses URLSession ATS for http:// Core URLs.
        let res = try await CleartextHTTP.request(
            method: "GET",
            url: url,
            headers: headers,
            body: nil,
            timeout: 30
        )
        try throwIfHTTPStatus(res.status, body: res.body)
        return try JSONSerialization.jsonObject(with: res.body) as? [String: Any] ?? [:]
    }

    private func postJSON(path: String, body: [String: Any], auth: Bool) async throws -> [String: Any] {
        guard let url = URL(string: normalizedBase() + path) else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]
        if auth, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let res = try await CleartextHTTP.request(
            method: "POST",
            url: url,
            headers: headers,
            body: bodyData,
            timeout: 120
        )
        try throwIfHTTPStatus(res.status, body: res.body)
        return try JSONSerialization.jsonObject(with: res.body) as? [String: Any] ?? [:]
    }

    private func throwIfHTTPStatus(_ status: Int, body: Data) throws {
        if status == 401 {
            throw NSError(domain: "core", code: 401, userInfo: [NSLocalizedDescriptionKey: "unauthorized — re-pair"])
        }
        if status == 0 {
            throw NSError(domain: "core", code: -1, userInfo: [NSLocalizedDescriptionKey: "서버 응답 없음 — Core URL·Tailscale·Mac 게이트웨이를 확인하세요"])
        }
        if status >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
                ?? String(data: body, encoding: .utf8)
                ?? "HTTP \(status)"
            throw NSError(domain: "core", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
