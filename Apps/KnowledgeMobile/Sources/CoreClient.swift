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
    @Published public var dietSuggestTitle: String = ""
    @Published public var dietSuggestSubtitle: String = ""
    /// W0 assistant hub fields from `assistant.today`.
    @Published public var bodyLine: String = ""
    @Published public var knowledgeLine: String = ""
    @Published public var timelinePreview: [[String: Any]] = []
    @Published public var nextActionLabel: String = ""
    @Published public var healthSyncLine: String = ""
    @Published public var gaps: [[String: Any]] = []
    @Published public var sleepHint: String = ""
    @Published public var streakDays: Int = 0
    @Published public var weekNarrative: String = ""
    @Published public var inboxOpenCount: Int = 0

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
        // Preflight: can we reach Core at all?
        let probe = await probeCoreHealth()
        if !probe.ok {
            lastError = probe.message
            connected = false
            return
        }
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
                let raw = res["error"] as? String ?? "pair failed"
                lastError = friendlyPairError(raw)
            }
        } catch {
            lastError = friendlyPairError(error.localizedDescription)
            connected = false
        }
    }

    /// Unauthenticated health probe for recovery UX (G8).
    public func probeCoreHealth() async -> (ok: Bool, message: String, core: String?) {
        baseURL = normalizedBase()
        do {
            let res = try await getJSON(path: "/v1/health", auth: false)
            let ok = (res["ok"] as? Bool) ?? true
            let name = res["core"] as? String
            if ok {
                return (true, "Core 응답 OK\(name.map { " · \($0)" } ?? "")", name)
            }
            return (false, "Core가 응답했지만 ok=false 예요. Mac 앱을 재시작해 보세요.", name)
        } catch {
            return (false, friendlyPairError(error.localizedDescription), nil)
        }
    }

    public func friendlyPairError(_ msg: String) -> String {
        let m = msg.lowercased()
        if m.contains("app transport security") || m.contains("secure connection") {
            return "보안 정책 오류예요. 앱을 삭제 후 Xcode에서 다시 설치해 주세요."
        }
        if m.contains("timed out") || m.contains("timeout") || m.contains("time out") {
            return "연결 시간이 초과됐어요. Mac·Tailscale이 켜져 있는지, URL의 IP가 맞는지 확인하세요."
        }
        if m.contains("could not connect") || m.contains("connection refused") || m.contains("offline")
            || m.contains("network") || m.contains("//1") || m.contains("failed to connect") {
            return "Mac Core에 닿지 않아요. ① Knowledge.app 실행 ② Tailscale 연결 ③ URL이 http://100.x:8741 형태인지 확인하세요."
        }
        if m.contains("401") || m.contains("unauthorized") || m.contains("invalid") || m.contains("code")
            || m.contains("expired") {
            return "코드가 틀리거나 만료됐을 수 있어요. Mac 설정 → 모바일 연결에서 새 코드를 받아 주세요."
        }
        if m.contains("404") {
            return "주소를 찾을 수 없어요. 포트 8741과 경로가 맞는지 확인하세요."
        }
        return msg
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
        await syncHealthKitIfPossible()
        await refreshAssistantToday()
    }

    /// W1 pull-on-open: Health → Core health.ingest (idempotent).
    public func syncHealthKitIfPossible(forceAuth: Bool = false) async {
        guard isPaired else { return }
        let hk = HealthKitBridge.shared
        guard hk.isAvailable else { return }
        if forceAuth || hk.authorizationRequested {
            if forceAuth {
                let ok = await hk.requestAuthorization()
                if !ok {
                    healthSyncLine = hk.lastError ?? "건강 권한 필요"
                    return
                }
            }
            do {
                let samples = try await hk.collectSamples(days: 7)
                guard !samples.isEmpty else {
                    healthSyncLine = "건강 데이터 없음 (최근 7일)"
                    return
                }
                let result = try await healthIngest(samples: samples)
                let accepted = result["accepted"] as? Int ?? Int(result["accepted"] as? Double ?? 0)
                let deduped = result["deduped"] as? Int ?? Int(result["deduped"] as? Double ?? 0)
                healthSyncLine = "건강 동기 \(accepted)건 반영 · 중복 \(deduped)"
                hk.lastSyncSummary = healthSyncLine
            } catch {
                healthSyncLine = error.localizedDescription
                hk.lastError = error.localizedDescription
            }
        }
    }

    public func healthIngest(samples: [[String: Any]]) async throws -> [String: Any] {
        try await dietRPC("health.ingest", params: ["samples": samples])
    }

    /// Composed briefing (body + knowledge + timeline). Falls back silently if RPC missing.
    public func refreshAssistantToday() async {
        guard isPaired else {
            bodyLine = ""
            knowledgeLine = ""
            timelinePreview = []
            nextActionLabel = ""
            return
        }
        do {
            let result = try await dietRPC("assistant.today", params: [:])
            if let body = result["body"] as? [String: Any] {
                bodyLine = body["line"] as? String ?? ""
                sleepHint = body["sleep_hint"] as? String ?? ""
                if let s = body["streak_days"] as? Int {
                    streakDays = s
                } else if let s = body["streak_days"] as? Double {
                    streakDays = Int(s)
                }
                if let suggest = body["suggest"] as? [String: Any] {
                    dietSuggestTitle = suggest["title"] as? String ?? dietSuggestTitle
                    dietSuggestSubtitle = suggest["subtitle"] as? String ?? dietSuggestSubtitle
                }
            }
            if let knowledge = result["knowledge"] as? [String: Any] {
                knowledgeLine = knowledge["line"] as? String ?? ""
                if let n = knowledge["review_pending"] as? Int {
                    reviewCount = n
                } else if let n = knowledge["review_pending"] as? Double {
                    reviewCount = Int(n)
                }
                if let n = knowledge["inbox_open"] as? Int {
                    inboxOpenCount = n
                } else if let n = knowledge["inbox_open"] as? Double {
                    inboxOpenCount = Int(n)
                }
            }
            gaps = result["gaps"] as? [[String: Any]] ?? []
            if let events = result["timeline"] as? [[String: Any]] {
                timelinePreview = Array(events.suffix(5))
            }
            if let actions = result["next_actions"] as? [[String: Any]],
               let first = actions.first {
                nextActionLabel = first["label"] as? String ?? ""
            }
            if bodyLine.isEmpty == false {
                dietLine = bodyLine
            }
            LocalNotify.scheduleGapsIfNeeded(gaps: gaps, reviewCount: reviewCount)
        } catch {
            // Older gateway without assistant.* — keep diet/review paths.
        }
    }

    public func fetchWeekReview() async throws -> [String: Any] {
        let result = try await dietRPC("assistant.week_review", params: [:])
        weekNarrative = result["narrative"] as? String ?? ""
        return result
    }

    public func inboxList() async throws -> [[String: Any]] {
        let result = try await dietRPC("inbox.list", params: [:])
        if let n = result["open_count"] as? Int { inboxOpenCount = n }
        return result["items"] as? [[String: Any]] ?? []
    }

    public func inboxCreate(text: String) async throws {
        _ = try await dietRPC("inbox.create", params: ["text": text])
        _ = try? await inboxList()
    }

    public func inboxPromote(id: String) async throws {
        _ = try await dietRPC("inbox.promote", params: ["id": id])
        _ = try? await inboxList()
    }

    public func inboxDelete(id: String) async throws {
        _ = try await dietRPC("inbox.delete", params: ["id": id])
        _ = try? await inboxList()
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
        try await askRPC(method: "knowledge.ask.fast", q: q, useLlama: false)
    }

    /// Full path: retrieve + cloud-first refine (preferred for mobile quality).
    public func ask(q: String) async throws -> (answer: String, engine: String, citations: [[String: Any]]) {
        try await askRPC(method: "knowledge.ask", q: q, useLlama: true)
    }

    private func askRPC(method: String, q: String, useLlama: Bool) async throws -> (answer: String, engine: String, citations: [[String: Any]]) {
        let rpc = try await rpc(method: method, params: [
            "q": q,
            "limit": 8,
            "use_llama": useLlama,
        ])
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
        let res = try await postJSON(path: "/v1/chat", body: ["message": message, "mode": "knowledge"], auth: true)
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

    /// Returns whether the server removed a row.
    @discardableResult
    public func dietDeleteMeal(id: String) async throws -> Bool {
        let r = try await dietRPC("diet.delete_meal", params: ["id": id])
        if let b = r["deleted"] as? Bool { return b }
        if let n = r["deleted"] as? NSNumber { return n.boolValue }
        return true
    }

    @discardableResult
    public func dietDeleteWorkout(id: String) async throws -> Bool {
        let r = try await dietRPC("diet.delete_workout", params: ["id": id])
        if let b = r["deleted"] as? Bool { return b }
        if let n = r["deleted"] as? NSNumber { return n.boolValue }
        return true
    }

    public func dietSuggest() async throws -> (title: String, subtitle: String, slot: String?) {
        let r = try await dietRPC("diet.suggest", params: [:])
        return (
            r["title"] as? String ?? "기록해 볼까요?",
            r["subtitle"] as? String ?? "",
            r["slot"] as? String
        )
    }

    public func dietSetProfile(
        heightCm: Double,
        weightKg: Double,
        age: Int,
        sex: String,
        targetWeightKg: Double,
        activity: String,
        applyGoals: Bool = true
    ) async throws -> [String: Any] {
        try await dietRPC("diet.profile.set", params: [
            "height_cm": heightCm,
            "weight_kg": weightKg,
            "age": age,
            "sex": sex,
            "target_weight_kg": targetWeightKg,
            "activity": activity,
            "apply_goals": applyGoals,
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
        guard isPaired else {
            dietLine = ""
            dietSuggestTitle = ""
            dietSuggestSubtitle = ""
            return
        }
        if let s = try? await dietSuggest() {
            dietSuggestTitle = s.title
            dietSuggestSubtitle = s.subtitle
        }
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
