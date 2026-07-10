import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC
import KnowledgeWorkers
#if canImport(Darwin)
import Darwin
#endif

/// Minimal HTTP/1.1 server for Core mobile gateway (Tailscale / LAN).
public final class MobileHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private let knowledgeRoot: URL
    private let store: KnowledgeStore
    private let pipeline: PipelineService
    private let pairing: PairingStore
    private let diet: DietStore
    private let inbox: InboxStore
    private let coreName: String
    private var serverFD: Int32 = -1
    private var acceptThread: Thread?

    public init(
        port: UInt16,
        knowledgeRoot: URL,
        store: KnowledgeStore,
        pipeline: PipelineService,
        coreName: String = "knowledge-core"
    ) {
        self.port = port
        self.knowledgeRoot = knowledgeRoot
        self.store = store
        self.pipeline = pipeline
        self.pairing = PairingStore(knowledgeRoot: knowledgeRoot)
        self.diet = DietStore(knowledgeRoot: knowledgeRoot)
        self.inbox = InboxStore(knowledgeRoot: knowledgeRoot)
        self.coreName = coreName
    }

    public func start() throws {
        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw URLError(.cannotCreateFile) }
        var yes: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
        let bindOk: Int32 = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOk == 0 else { throw URLError(.cannotConnectToHost) }
        guard listen(serverFD, 16) == 0 else { throw URLError(.cannotConnectToHost) }

        let fd = serverFD
        let thread = Thread { [weak self] in
            while true {
                var clientAddr = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let client: Int32 = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(fd, $0, &len)
                    }
                }
                if client < 0 { continue }
                let loopback = Self.isLoopback(clientAddr)
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.serve(client, fromLoopback: loopback)
                }
            }
        }
        thread.name = "knowledge.gateway.accept"
        thread.start()
        acceptThread = thread
        fputs("knowledge-gateway: HTTP :\(port) (pair + rpc + chat + diet)\n", stderr)
    }

    public func emitPairCode() throws -> String {
        let r = try pairing.startPairing()
        fputs("PAIR CODE: \(r.code) (expires \(r.expiresIn)s)\n", stderr)
        return r.code
    }

    private static func isLoopback(_ addr: sockaddr_in) -> Bool {
        let hostOrder = UInt32(bigEndian: addr.sin_addr.s_addr)
        // 127.0.0.0/8
        return (hostOrder >> 24) == 127
    }

    private func serve(_ fd: Int32, fromLoopback: Bool) {
        defer { close(fd) }
        var buffer = Data()
        var tmp = [UInt8](repeating: 0, count: 8192)
        // Read until headers complete and body present
        while true {
            let n = read(fd, &tmp, tmp.count)
            if n <= 0 { return }
            buffer.append(contentsOf: tmp[0..<n])
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 1024 * 1024 { return }
                continue
            }
            let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
            let headerStr = String(data: headerData, encoding: .utf8) ?? ""
            let cl = contentLength(headerStr)
            let bodyStart = headerEnd.upperBound
            if buffer.count - bodyStart < cl {
                continue
            }
            let body = cl > 0 ? buffer.subdata(in: bodyStart..<(bodyStart + cl)) : Data()
            let response = route(header: headerStr, body: body, fromLoopback: fromLoopback)
            _ = response.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return write(fd, base, response.count)
            }
            return
        }
    }

    private func contentLength(_ header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let v = line.split(separator: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespaces)
                return Int(v) ?? 0
            }
        }
        return 0
    }

    private var localPeer: PeerIdentity {
        PeerIdentity(uid: getuid(), pid: getpid())
    }

    private func route(header: String, body: Data, fromLoopback: Bool) -> Data {
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let reqLine = lines.first else { return http(400, ["error": "bad request"]) }
        let parts = reqLine.split(separator: " ")
        guard parts.count >= 2 else { return http(400, ["error": "bad request"]) }
        let method = String(parts[0])
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])
        let auth = lines.first(where: { $0.lowercased().hasPrefix("authorization:") })
            .map { String($0.dropFirst("Authorization:".count)).trimmingCharacters(in: .whitespaces) }

        do {
            switch (method, path) {
            case ("OPTIONS", _):
                return httpCORS()
            case ("GET", "/v1/health"), ("GET", "/health"):
                return try handleCoreHealth()
            case ("POST", "/v1/pair/start"):
                // Product rule: only Mac-local can mint codes (Settings UI / CLI on loopback).
                guard fromLoopback else {
                    return http(403, ["error": "pair/start is loopback-only — use Mac Settings or CLI"])
                }
                let r = try pairing.startPairing()
                return http(200, ["code": r.code, "expires_in": r.expiresIn, "core_name": coreName])
            case ("POST", "/v1/pair/complete"):
                let obj = try jsonObject(body)
                let r = try pairing.completePairing(
                    code: obj["code"] as? String ?? "",
                    deviceName: obj["device_name"] as? String ?? "iPhone"
                )
                return http(200, [
                    "token": r.token,
                    "device_id": r.deviceId,
                    "core_name": coreName,
                ])
            case ("GET", "/v1/pair/status"):
                guard let dev = pairing.authorize(bearer: auth) else { return http(401, ["error": "unauthorized"]) }
                return http(200, ["ok": true, "device_id": dev.id, "name": dev.name, "core_name": coreName])
            case ("POST", "/v1/pair/revoke"):
                guard let dev = pairing.authorize(bearer: auth) else { return http(401, ["error": "unauthorized"]) }
                try pairing.revoke(deviceId: dev.id)
                return http(200, ["revoked": true])
            case ("POST", "/v1/rpc"):
                guard pairing.authorize(bearer: auth) != nil else { return http(401, ["error": "unauthorized"]) }
                return try handleRPC(body)
            case ("POST", "/v1/chat"):
                guard pairing.authorize(bearer: auth) != nil else { return http(401, ["error": "unauthorized"]) }
                return try handleChat(body)
            default:
                return http(404, ["error": "not found", "path": path])
            }
        } catch let e as PairingError {
            return http(400, ["error": e.description])
        } catch {
            return http(500, ["error": String(describing: error)])
        }
    }

    /// Local helper for Mac UI: list paired devices (no secrets).
    public func listPairedDevices() -> [[String: String]] {
        pairing.listDevices().map {
            ["id": $0.id, "name": $0.name, "created_at": $0.createdAt]
        }
    }

    private func handleCoreHealth() throws -> Data {
        let res = pipeline.handle(request: JSONRPCRequest(method: RPCMethod.health.rawValue), peer: localPeer)
        var out: [String: Any] = [
            "ok": true,
            "core": coreName,
            "gateway": "m4",
            "services": ["knowledge": true, "diet": true, "assistant": true, "inbox": true, "health": true],
        ]
        if let r = res.result { out["knowledge"] = jsonAny(r) }
        out["diet"] = diet.daySummary()
        return http(200, out)
    }

    private func handleRPC(_ body: Data) throws -> Data {
        guard let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return http(400, ["error": "invalid json"])
        }
        let id = obj["id"]
        let method = obj["method"] as? String ?? ""
        let params = obj["params"]

        if method.hasPrefix("core.") {
            return try handleCoreMethod(method: method, id: id)
        }
        if method.hasPrefix("assistant.") || method.hasPrefix("timeline.") {
            return try handleAssistantMethod(method: method, id: id, params: params)
        }
        if method.hasPrefix("health.") {
            return try handleHealthMethod(method: method, id: id, params: params)
        }
        if method.hasPrefix("inbox.") {
            return try handleInboxMethod(method: method, id: id, params: params)
        }
        if method.hasPrefix("diet.") {
            return try handleDietMethod(method: method, id: id, params: params)
        }
        if method == "knowledge.ask" || method == "knowledge.ask.fast" {
            return try handleKnowledgeAsk(method: method, id: id, params: params)
        }
        let mapped: String
        var mappedParams: Any? = params
        switch method {
        case "knowledge.health": mapped = RPCMethod.health.rawValue
        case "knowledge.search": mapped = RPCMethod.search.rawValue
        case "knowledge.review.accept": mapped = RPCMethod.meetingReviewAccept.rawValue
        case "knowledge.review.list":
            mapped = RPCMethod.meetingList.rawValue
            var p = params as? [String: Any] ?? [:]
            p["status"] = "review_needed"
            mappedParams = p
        case "knowledge.meetings": mapped = RPCMethod.meetingList.rawValue
        default: mapped = method
        }
        let req = JSONRPCRequest(
            id: jsonRPCId(id),
            method: mapped,
            params: mappedParams.map { JSONValue.fromJSONObject($0) } ?? .object([:])
        )
        let res = pipeline.handle(request: req, peer: localPeer)
        return jsonRPCResponse(id: id, result: res.result, error: res.error)
    }

    private func handleCoreMethod(method: String, id: Any?) throws -> Data {
        switch method {
        case "core.ping":
            return jsonRPCResponse(id: id, result: .object(["pong": .bool(true)]), error: nil)
        case "core.services":
            return jsonRPCResponse(id: id, result: .object([
                "knowledge": .bool(true),
                "diet": .bool(true),
                "assistant": .bool(true),
            ]), error: nil)
        case "core.health":
            let data = try handleCoreHealth()
            if let range = data.range(of: Data("\r\n\r\n".utf8)) {
                let body = data.subdata(in: range.upperBound..<data.endIndex)
                if let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(obj), error: nil)
                }
            }
            return jsonRPCResponse(id: id, result: .object(["ok": .bool(true)]), error: nil)
        default:
            return jsonRPCResponse(id: id, result: nil, error: .methodNotFound)
        }
    }

    /// W0–W2 assistant surface — composes diet + review + gaps + week (no SoT dump).
    private func handleAssistantMethod(method: String, id: Any?, params: Any?) throws -> Data {
        switch method {
        case "assistant.today":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(buildAssistantToday()), error: nil)
        case "assistant.week_review":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(buildWeekReview()), error: nil)
        case "assistant.gaps":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject([
                "gaps": diet.missingLogChecklist(),
                "sleep_hint": diet.sleepCoachHint() as Any,
            ]), error: nil)
        case "timeline.list":
            var events = diet.timelineEvents()
            let reviewN = reviewPendingCount()
            if reviewN > 0 {
                events.append([
                    "ts": ISO8601DateFormatter().string(from: Date()),
                    "type": "review",
                    "title": "확인 대기 \(reviewN)건",
                    "source": "knowledge",
                    "id": "review-pending",
                ])
            }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject([
                "events": events,
                "count": events.count,
            ]), error: nil)
        default:
            return jsonRPCResponse(id: id, result: nil, error: .methodNotFound)
        }
    }

    private func handleInboxMethod(method: String, id: Any?, params: Any?) throws -> Data {
        let p = params as? [String: Any] ?? [:]
        switch method {
        case "inbox.create":
            let text = (p["text"] as? String) ?? (p["message"] as? String) ?? ""
            let item = try inbox.create(text: text)
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(inbox.asDict(item)), error: nil)
        case "inbox.list":
            let include = (p["include_promoted"] as? Bool) ?? false
            let items = inbox.list(includePromoted: include).map { inbox.asDict($0) }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject([
                "items": items,
                "open_count": inbox.openCount(),
            ]), error: nil)
        case "inbox.promote":
            guard let iid = p["id"] as? String, !iid.isEmpty else {
                return jsonRPCResponse(id: id, result: nil, error: .invalidParams)
            }
            let item = try inbox.promote(id: iid)
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(inbox.asDict(item)), error: nil)
        case "inbox.delete":
            guard let iid = p["id"] as? String, !iid.isEmpty else {
                return jsonRPCResponse(id: id, result: nil, error: .invalidParams)
            }
            try inbox.delete(id: iid)
            return jsonRPCResponse(id: id, result: .object(["deleted": .bool(true)]), error: nil)
        default:
            return jsonRPCResponse(id: id, result: nil, error: .methodNotFound)
        }
    }

    private func buildAssistantToday() -> [String: Any] {
        let day = diet.daySummary()
        let totals = day["totals"] as? [String: Any] ?? [:]
        let goals = diet.goalsDict()
        let suggest = diet.suggestedAction()
        let reviewN = reviewPendingCount()
        let gaps = diet.missingLogChecklist()
        let sleepHint = diet.sleepCoachHint()
        let streak = diet.activityStreak()
        let inboxOpen = inbox.openCount()
        var timeline = diet.timelineEvents()
        if reviewN > 0 {
            timeline.append([
                "ts": ISO8601DateFormatter().string(from: Date()),
                "type": "review",
                "title": "확인 대기 \(reviewN)건",
                "source": "knowledge",
                "id": "review-pending",
            ])
        }

        var nextActions: [[String: Any]] = []
        if reviewN > 0 {
            nextActions.append(["kind": "review", "label": "확인함 \(reviewN)건 보기"])
        }
        if let firstGap = gaps.first {
            var gapAction: [String: Any] = [
                "kind": "gap",
                "label": firstGap["label"] as? String ?? "빠진 기록 채우기",
            ]
            if let slot = firstGap["slot"] as? String {
                gapAction["slot"] = slot
            }
            nextActions.append(gapAction)
        }
        nextActions.append([
            "kind": "diet_suggest",
            "label": suggest.title,
            "subtitle": suggest.subtitle,
        ])
        if let slot = suggest.slot {
            nextActions[nextActions.count - 1]["slot"] = slot.rawValue
        }
        if inboxOpen > 0 {
            nextActions.append(["kind": "inbox", "label": "인박스 \(inboxOpen)건 정리"])
        }

        let bodyLine: String = {
            if let text = day["summary_text"] as? String, !text.isEmpty { return text }
            let kcal = totals["kcal"] as? Double ?? 0
            let protein = totals["protein_g"] as? Double ?? 0
            return String(format: "오늘 %.0f kcal · 단백질 %.0fg", kcal, protein)
        }()

        var body: [String: Any] = [
            "line": bodyLine,
            "kcal": totals["kcal"] as? Double ?? 0,
            "protein_g": totals["protein_g"] as? Double ?? 0,
            "workout_minutes": totals["workout_minutes"] as? Int ?? 0,
            "meal_count": totals["meal_count"] as? Int ?? 0,
            "target_kcal": goals["target_kcal"] as? Double ?? 0,
            "target_protein_g": goals["target_protein_g"] as? Double ?? 0,
            "suggest": [
                "title": suggest.title,
                "subtitle": suggest.subtitle,
            ] as [String: Any],
            "streak_days": streak,
        ]
        if let sleepHint { body["sleep_hint"] = sleepHint }

        return [
            "date": day["date"] as? String ?? "",
            "body": body,
            "knowledge": [
                "review_pending": reviewN,
                "line": reviewN > 0 ? "저장 전 요약 \(reviewN)건" : "확인할 요약 없음",
                "inbox_open": inboxOpen,
            ] as [String: Any],
            "gaps": gaps,
            "timeline": timeline,
            "next_actions": nextActions,
            "version": 2,
        ]
    }

    private func buildWeekReview() -> [String: Any] {
        var week = diet.weekReview()
        let streak = diet.activityStreak()
        let sleepHint = diet.sleepCoachHint()
        let reviewN = reviewPendingCount()
        var narrative: [String] = []
        if let summary = week["summary_text"] as? String { narrative.append(summary) }
        narrative.append("연속 기록 \(streak)일")
        if let sleepHint { narrative.append(sleepHint) }
        if reviewN > 0 { narrative.append("확인 대기 요약 \(reviewN)건") }
        week["streak_days"] = streak
        week["narrative"] = narrative.joined(separator: "\n")
        week["narrative_lines"] = narrative
        week["review_pending"] = reviewN
        week["inbox_open"] = inbox.openCount()
        if let sleepHint { week["sleep_hint"] = sleepHint }
        // week buckets = days array already
        return week
    }

    private func reviewPendingCount() -> Int {
        let req = JSONRPCRequest(
            id: .string("assistant-review"),
            method: RPCMethod.meetingList.rawValue,
            params: .object(["status": .string("review_needed")])
        )
        let res = pipeline.handle(request: req, peer: localPeer)
        guard let result = res.result else { return 0 }
        if case .array(let arr) = result { return arr.count }
        if case .object(let obj) = result {
            if let m = obj["meetings"], case .array(let arr) = m { return arr.count }
            if let m = obj["items"], case .array(let arr) = m { return arr.count }
        }
        // Fallback via Any bridge
        let any = jsonAny(result)
        if let arr = any as? [Any] { return arr.count }
        if let dict = any as? [String: Any] {
            if let arr = dict["meetings"] as? [Any] { return arr.count }
            if let arr = dict["items"] as? [Any] { return arr.count }
        }
        return 0
    }

    private func handleHealthMethod(method: String, id: Any?, params: Any?) throws -> Data {
        let p = params as? [String: Any] ?? [:]
        switch method {
        case "health.ingest":
            let samples = p["samples"] as? [[String: Any]] ?? []
            let result = try diet.ingestHealthSamples(samples)
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(result), error: nil)
        case "health.sync_status":
            // Sensor SoT is Apple Health on device; Core only mirrors via ingest.
            return jsonRPCResponse(id: id, result: .object([
                "ok": .bool(true),
                "mirror": .string("diet"),
                "pull_mode": .string("app_open"),
                "mac_healthkit": .bool(false),
            ]), error: nil)
        default:
            return jsonRPCResponse(id: id, result: nil, error: .methodNotFound)
        }
    }

    private func handleDietMethod(method: String, id: Any?, params: Any?) throws -> Data {
        let p = params as? [String: Any] ?? [:]
        switch method {
        case "diet.ping":
            return jsonRPCResponse(id: id, result: .object([
                "ok": .bool(true),
                "enabled": .bool(true),
                "engine": .string("diet-inproc/v1"),
            ]), error: nil)
        case "diet.log_meal":
            let items: [String]
            if let arr = p["items"] as? [String] {
                items = arr
            } else if let s = p["items"] as? String {
                items = [s]
            } else if let note = p["note"] as? String, !note.isEmpty {
                items = [note]
            } else {
                items = ["meal"]
            }
            let meal = try diet.logMeal(
                items: items,
                kcal: doubleParam(p["kcal"]),
                proteinG: doubleParam(p["protein_g"] ?? p["proteinG"]),
                note: p["note"] as? String
            )
            var mealOut: [String: Any] = ["id": meal.id, "ts": meal.ts, "items": meal.items]
            if let k = meal.kcal { mealOut["kcal"] = k }
            if let pr = meal.proteinG { mealOut["protein_g"] = pr }
            if let n = meal.note { mealOut["note"] = n }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(mealOut), error: nil)
        case "diet.log_workout":
            let w = try diet.logWorkout(
                kind: p["kind"] as? String ?? "workout",
                minutes: intParam(p["minutes"]) ?? 0,
                intensity: p["intensity"] as? String
            )
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject([
                "id": w.id, "ts": w.ts, "kind": w.kind, "minutes": w.minutes,
            ]), error: nil)
        case "diet.log_metric":
            let m = try diet.logMetric(
                weightKg: doubleParam(p["weight_kg"] ?? p["weightKg"]),
                sleepH: doubleParam(p["sleep_h"] ?? p["sleepH"])
            )
            var out: [String: Any] = ["id": m.id, "ts": m.ts]
            if let w = m.weightKg { out["weight_kg"] = w }
            if let s = m.sleepH { out["sleep_h"] = s }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(out), error: nil)
        case "diet.delete_meal":
            guard let id = p["id"] as? String, !id.isEmpty else {
                return jsonRPCResponse(id: id, result: nil, error: .invalidParams)
            }
            try diet.deleteMeal(id: id)
            return jsonRPCResponse(id: id, result: .object(["deleted": .bool(true)]), error: nil)
        case "diet.delete_workout":
            guard let id = p["id"] as? String, !id.isEmpty else {
                return jsonRPCResponse(id: id, result: nil, error: .invalidParams)
            }
            try diet.deleteWorkout(id: id)
            return jsonRPCResponse(id: id, result: .object(["deleted": .bool(true)]), error: nil)
        case "diet.suggest":
            let s = diet.suggestedAction()
            var obj: [String: Any] = ["title": s.title, "subtitle": s.subtitle]
            if let slot = s.slot { obj["slot"] = slot.rawValue }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(obj), error: nil)
        case "diet.profile.get":
            if let pd = diet.profileDict() {
                return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(pd), error: nil)
            }
            return jsonRPCResponse(id: id, result: .object(["exists": .bool(false)]), error: nil)
        case "diet.profile.set":
            let sexRaw = (p["sex"] as? String) ?? "female"
            let actRaw = (p["activity"] as? String) ?? "light"
            let sex = DietProfile.Sex(rawValue: sexRaw) ?? .female
            let act = DietProfile.Activity(rawValue: actRaw) ?? .light
            let profile = DietProfile(
                heightCm: doubleParam(p["height_cm"]) ?? 165,
                weightKg: doubleParam(p["weight_kg"]) ?? 65,
                age: intParam(p["age"]) ?? 30,
                sex: sex,
                targetWeightKg: doubleParam(p["target_weight_kg"]) ?? 60,
                activity: act
            )
            try diet.setProfile(profile)
            let apply = (p["apply_goals"] as? Bool) ?? true
            if apply { try diet.applyRecommendedGoalsFromProfile() }
            var out: [String: Any] = diet.profileDict() ?? [:]
            out["goals"] = diet.goalsDict()
            if let plan = diet.planProjection() {
                out["plan"] = plan.asDict()
            }
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(out), error: nil)
        case "diet.plan":
            if let plan = diet.planProjection() {
                return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(plan.asDict()), error: nil)
            }
            return jsonRPCResponse(id: id, result: .object([
                "needs_profile": .bool(true),
                "eta_text": .string("키·몸무게·나이·성별·목표 체중을 입력하면 도달 시점을 계산해요."),
            ]), error: nil)
        case "diet.day_summary":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.daySummary()), error: nil)
        case "diet.week_review":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.weekReview()), error: nil)
        case "diet.coach":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.coach(message: p["message"] as? String)), error: nil)
        case "diet.dashboard":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.dashboardJSON()), error: nil)
        case "diet.goals", "diet.goals.get":
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.goalsDict()), error: nil)
        case "diet.goals.set":
            var g = diet.goals()
            if let v = doubleParam(p["target_kcal"]) { g.targetKcal = v }
            if let v = doubleParam(p["target_protein_g"]) { g.targetProteinG = v }
            if let v = intParam(p["weekly_workouts"]) { g.weeklyWorkouts = v }
            if let v = intParam(p["target_workout_minutes_per_day"]) { g.targetWorkoutMinutesPerDay = v }
            try diet.setGoals(g)
            return jsonRPCResponse(id: id, result: JSONValue.fromJSONObject(diet.goalsDict()), error: nil)
        default:
            return jsonRPCResponse(id: id, result: nil, error: .methodNotFound)
        }
    }

    private func doubleParam(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private func intParam(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private func handleKnowledgeAsk(method: String, id: Any?, params: Any?) throws -> Data {
        let p = params as? [String: Any] ?? [:]
        let q = (p["q"] as? String) ?? (p["question"] as? String) ?? ""
        let limit = (p["limit"] as? Int) ?? 8
        let final: KnowledgeRAG.Answer
        if method == "knowledge.ask.fast" {
            final = try KnowledgeRAG.askFast(question: q, store: store, topK: limit)
        } else {
            let fast = try KnowledgeRAG.askFast(question: q, store: store, topK: limit)
            final = KnowledgeRAG.refine(
                question: q,
                citations: fast.citations,
                knowledgeRoot: knowledgeRoot,
                useLlama: (p["use_llama"] as? Bool) ?? true
            ) ?? fast
        }
        let cites = final.citations.prefix(8).map { c -> JSONValue in
            .object([
                "unit_id": .string(c.unitId),
                "title": .string(c.title),
                "source_type": .string(c.sourceType),
                "snippet": .string(c.snippet),
                "score": .number(c.score),
            ])
        }
        return jsonRPCResponse(id: id, result: .object([
            "answer": .string(final.answer),
            "engine": .string(final.engine),
            "citations": .array(Array(cites)),
        ]), error: nil)
    }

    private func handleChat(_ body: Data) throws -> Data {
        let obj = try jsonObject(body)
        let message = obj["message"] as? String ?? ""
        let mode = (obj["mode"] as? String ?? "auto").lowercased()
        let intent = classifyIntent(message: message, mode: mode)

        if intent == "diet" {
            return try handleDietChat(message: message)
        }
        if intent == "mixed" {
            return try handleMixedChat(message: message)
        }

        let fast = try KnowledgeRAG.askFast(question: message, store: store, topK: 8)
        let answer = KnowledgeRAG.refine(
            question: message,
            citations: fast.citations,
            knowledgeRoot: knowledgeRoot,
            useLlama: true
        ) ?? fast
        let sources: [[String: Any]] = answer.citations.prefix(6).map {
            [
                "service": "knowledge",
                "title": $0.title,
                "snippet": $0.snippet,
                "unit_id": $0.unitId,
            ]
        }
        return http(200, [
            "answer": answer.answer,
            "engine": answer.engine,
            "sources": sources,
            "trace": ["intent:knowledge", "knowledge.ask"],
            "intent": "knowledge",
        ])
    }

    /// Cross-domain: aggregates body first, then knowledge retrieve (W2).
    private func handleMixedChat(message: String) throws -> Data {
        var trace: [String] = ["intent:mixed"]
        let coach = diet.coach(message: message)
        trace.append("diet.coach")
        let dayLine = (diet.daySummary()["summary_text"] as? String) ?? ""
        let sleep = diet.sleepCoachHint() ?? ""
        let week = diet.weekReview()
        let weekLine = (week["summary_text"] as? String) ?? ""

        let fast = try KnowledgeRAG.askFast(question: message, store: store, topK: 6)
        let knowledge = KnowledgeRAG.refine(
            question: message,
            citations: fast.citations,
            knowledgeRoot: knowledgeRoot,
            useLlama: true
        ) ?? fast
        trace.append("knowledge.ask")

        var parts: [String] = []
        parts.append("【몸】")
        if let a = coach["answer"] as? String, !a.isEmpty { parts.append(a) }
        if !dayLine.isEmpty { parts.append(dayLine) }
        if !weekLine.isEmpty { parts.append(weekLine) }
        if !sleep.isEmpty { parts.append(sleep) }
        parts.append("")
        parts.append("【지식】")
        parts.append(knowledge.answer)

        var sources: [[String: Any]] = [
            ["service": "diet", "title": "오늘·주간", "snippet": dayLine],
        ]
        for c in knowledge.citations.prefix(4) {
            sources.append([
                "service": "knowledge",
                "title": c.title,
                "snippet": c.snippet,
                "unit_id": c.unitId,
            ])
        }

        return http(200, [
            "answer": parts.joined(separator: "\n"),
            "engine": "mixed/\(knowledge.engine)",
            "sources": sources,
            "trace": trace,
            "intent": "mixed",
        ])
    }

    private func handleDietChat(message: String) throws -> Data {
        var trace: [String] = ["intent:diet"]
        // Heuristic log: "운동 … N분"
        if message.contains("운동") || message.lowercased().contains("workout") {
            let minutes = firstInt(in: message) ?? 20
            var kind = message
                .replacingOccurrences(of: "운동", with: "")
                .replacingOccurrences(of: "workout", with: "", options: .caseInsensitive)
            if let re = try? NSRegularExpression(pattern: "\\d+\\s*분") {
                kind = re.stringByReplacingMatches(in: kind, range: NSRange(kind.startIndex..., in: kind), withTemplate: "")
            }
            kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            let w = try diet.logWorkout(kind: kind.isEmpty ? "workout" : String(kind.prefix(40)), minutes: minutes, intensity: nil)
            trace.append("diet.log_workout")
            let day = diet.daySummary()
            return http(200, [
                "answer": "운동 기록했어요: \(w.kind) \(w.minutes)분.\n\(day["summary_text"] as? String ?? "")",
                "engine": "diet-rules/v1",
                "sources": [["service": "diet", "title": "workout", "snippet": "\(w.kind) \(w.minutes)m"]],
                "trace": trace,
            ])
        }
        // Heuristic meal if kcal or 먹/식사 present with content
        if message.contains("kcal") || message.contains("칼로리") || message.contains("먹") || message.contains("식사") || message.contains("점심") || message.contains("저녁") || message.contains("아침") {
            let kcal = firstDouble(in: message)
            let meal = try diet.logMeal(items: [message], kcal: kcal, proteinG: nil, note: message)
            trace.append("diet.log_meal")
            let day = diet.daySummary()
            return http(200, [
                "answer": "식사 기록했어요\(kcal.map { " (\(Int($0)) kcal)" } ?? "").\n\(day["summary_text"] as? String ?? "")",
                "engine": "diet-rules/v1",
                "sources": [["service": "diet", "title": "meal", "snippet": meal.items.joined(separator: ", ")]],
                "trace": trace,
            ])
        }
        // Default: coach + day summary
        let coach = diet.coach(message: message)
        trace.append("diet.coach")
        return http(200, [
            "answer": coach["answer"] as? String ?? "",
            "engine": coach["engine"] as? String ?? "diet-rules/v1",
            "sources": [["service": "diet", "title": "오늘", "snippet": (diet.daySummary()["summary_text"] as? String) ?? ""]],
            "trace": trace,
        ])
    }

    private func classifyIntent(message: String, mode: String) -> String {
        if mode == "diet" { return "diet" }
        if mode == "knowledge" { return "knowledge" }
        if mode == "mixed" { return "mixed" }
        let lower = message.lowercased()
        let dietCues = ["먹", "식사", "운동", "칼로리", "체중", "다이어트", "단백질", "수면", "workout", "calorie", "meal", "점심", "저녁", "아침", "kcal", "체중"]
        let knowledgeCues = ["회의", "미팅", "요약", "노트", "기억", "vault", "지난주", "지난번", "프로젝트", "액션", "할 일", "결정"]
        let crossCues = ["그리고", "vs", "대비", "비교", "같이", "동시에", "이번 주", "이번주", "목표랑", "목표와"]
        let hasDiet = dietCues.contains(where: { lower.contains($0) || message.contains($0) })
        let hasKnowledge = knowledgeCues.contains(where: { message.contains($0) || lower.contains($0) })
        let hasCross = crossCues.contains(where: { message.contains($0) || lower.contains($0) })
        if (hasDiet && hasKnowledge) || (hasDiet && hasCross) || (hasKnowledge && hasCross && hasDiet) {
            return "mixed"
        }
        // Explicit templates
        if message.contains("단백질") && (message.contains("회의") || message.contains("목표")) {
            return "mixed"
        }
        if hasDiet { return "diet" }
        return "knowledge"
    }

    private func firstInt(in text: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: "(\\d+)")
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern?.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private func firstDouble(in text: String) -> Double? {
        let pattern = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)")
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern?.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    private func httpCORS() -> Data {
        let head = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        return Data(head.utf8)
    }

    private func http(_ status: Int, _ obj: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 401 ? "Unauthorized" : "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return d
    }

    private func jsonRPCId(_ id: Any?) -> JSONRPCID {
        if let i = id as? Int { return .int(i) }
        if let d = id as? Double { return .int(Int(d)) }
        if let s = id as? String { return .string(s) }
        return .int(1)
    }

    private func jsonRPCResponse(id: Any?, result: JSONValue?, error: JSONRPCError?) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "id": id ?? 1]
        if let error {
            obj["error"] = ["code": error.code, "message": error.message]
        } else if let result {
            obj["result"] = jsonAny(result)
        } else {
            obj["result"] = NSNull()
        }
        return http(200, obj)
    }

    private func jsonAny(_ v: JSONValue) -> Any {
        switch v {
        case .null: return NSNull()
        case let .bool(b): return b
        case let .number(n): return n
        case let .string(s): return s
        case let .array(a): return a.map { jsonAny($0) }
        case let .object(o):
            var d: [String: Any] = [:]
            for (k, val) in o { d[k] = jsonAny(val) }
            return d
        }
    }
}

extension JSONValue {
    static func fromJSONObject(_ any: Any) -> JSONValue {
        switch any {
        case let b as Bool: return .bool(b)
        case let i as Int: return .number(Double(i))
        case let d as Double: return .number(d)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map { fromJSONObject($0) })
        case let o as [String: Any]:
            var m: [String: JSONValue] = [:]
            for (k, v) in o { m[k] = fromJSONObject(v) }
            return .object(m)
        default: return .null
        }
    }
}
