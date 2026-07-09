import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeWorkers

/// Self-verify dogfood without UI clicks.
/// Usage: knowledge-dogfood [--root ~/Knowledge] [--reindex] [--pipeline] [--commit]

func expand(_ path: String) -> String {
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2))).path
    }
    return path
}

var rootPath = KnowledgePaths.defaultKnowledgeRoot.path
var doReindex = true
var doPipeline = true
var doCommit = true
var args = Array(CommandLine.arguments.dropFirst())
while let a = args.first {
    args.removeFirst()
    switch a {
    case "--root": rootPath = expand(args.removeFirst())
    case "--reindex": doReindex = true
    case "--no-reindex": doReindex = false
    case "--pipeline": doPipeline = true
    case "--no-pipeline": doPipeline = false
    case "--commit": doCommit = true
    case "--no-commit": doCommit = false
    case "--help", "-h":
        print("knowledge-dogfood [--root PATH] [--reindex|--no-reindex] [--pipeline|--no-pipeline] [--commit|--no-commit]")
        exit(0)
    default:
        fputs("unknown arg \(a)\n", stderr)
        exit(2)
    }
}

let root = URL(fileURLWithPath: expand(rootPath), isDirectory: true)
try KnowledgePaths.ensureLayout(at: root)
let dbPath = root.appendingPathComponent("index/knowledge.db").path
let store = try KnowledgeStore(path: dbPath)
let cfg = AppConfig.load(knowledgeRoot: root)
let vault = cfg.vaultURL

var failures: [String] = []
func ok(_ s: String) { print("OK  \(s)") }
func fail(_ s: String) { print("FAIL \(s)"); failures.append(s) }

print("== knowledge-dogfood ==")
print("root=\(root.path)")
print("vault=\(vault.path)")

if cfg.ensureVaultDirectory() != nil {
    fail("vault not writable")
} else {
    ok("vault ready")
}

// 1) reindex hash vectors
if doReindex {
    let ids = try store.listKnowledgeUnitIds()
    var n = 0
    for uid in ids {
        try LocalHashEmbedder.indexUnit(store: store, unitId: uid)
        n += 1
        if n % 50 == 0 { print("  … embedded \(n)/\(ids.count)") }
    }
    ok("reindex vectors units=\(n)")
}

// 2) synthetic pipeline
let dogfoodId = "dogfood-\(Int(Date().timeIntervalSince1970))"
if doPipeline {
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("transcripts", isDirectory: true),
        withIntermediateDirectories: true
    )
    let transcript = TranscriptDocument(
        meetingId: dogfoodId,
        asrModelId: "dogfood-synth",
        language: "ko",
        segments: [
            TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 2500, text: "오늘 스프린트에서 결제 API 스펙을 확정하기로 결정했습니다."),
            TranscriptSegment(index: 1, tStartMs: 2500, tEndMs: 5000, text: "김민수가 월요일까지 OpenAPI 초안을 작성해야 합니다."),
            TranscriptSegment(index: 2, tStartMs: 5000, tEndMs: 7500, text: "타임아웃은 3초로 맞추고 미해결 이슈는 다음 주 논의합니다."),
            TranscriptSegment(index: 3, tStartMs: 7500, tEndMs: 10000, text: "유니크독푸드토큰XYZ 로 검색 검증합니다."),
        ]
    )
    let tRel = "transcripts/\(dogfoodId).json"
    try JSONEncoder().encode(transcript).write(to: root.appendingPathComponent(tRel), options: .atomic)

    try store.insertMeeting(MeetingRecord(
        id: dogfoodId,
        title: "Dogfood 검증 미팅",
        mode: "dogfood",
        status: .transcribed,
        audioPath: "audio/raw/\(dogfoodId).wav",
        audioSha256: "dogfood",
        audioDurationMs: 10_000,
        transcriptPath: tRel,
        transcriptSegmentCount: 4,
        asrModelId: "dogfood-synth"
    ))

    let runner = OfflinePipelineRunner(store: store, knowledgeRoot: root, language: "ko")
    for _ in 0..<6 {
        if !(try runner.tick()) { break }
    }

    guard let m = try store.getMeeting(id: dogfoodId) else {
        fail("pipeline meeting missing")
        print("== dogfood FAIL ==")
        exit(1)
    }

    if m.status == .reviewNeeded {
        ok("pipeline → review_needed candidate=\(m.candidatePath ?? "?")")
    } else {
        fail("pipeline status=\(m.status.rawValue) expected review_needed")
    }

    // 3) commit
    if doCommit, m.status == .reviewNeeded, let cand = m.candidatePath {
        let data = try Data(contentsOf: root.appendingPathComponent(cand))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let summary = try dec.decode(MeetingSummaryV1.self, from: data)

        _ = try store.transition(
            meetingId: dogfoodId,
            to: .commitPending,
            ctx: GuardContext(stage1OK: true, stage2: m.stage2Outcome ?? .pass, humanAccepted: true),
            event: "dogfood.accept"
        )
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let (rel, hash) = try VaultCommit.commit(
            vaultPath: vault,
            meetingId: dogfoodId,
            title: m.title ?? "Dogfood",
            summary: summary,
            transcriptRel: m.transcriptPath
        )
        let committed = try store.transition(
            meetingId: dogfoodId,
            to: .committed,
            ctx: GuardContext(vaultFinalExists: true, indexCommittedOK: true),
            event: "dogfood.commit"
        ) { rec in
            rec.vaultPath = rel
            rec.vaultContentHash = hash
            rec.acceptedAt = ISO8601DateFormatter().string(from: Date())
        }
        let actions = summary.actionItems.enumerated().map { i, a in
            (id: "\(dogfoodId)-a\(i)", text: a.text, owner: a.owner, dueOn: a.dueOn)
        }
        try store.replaceActionItems(meetingId: dogfoodId, items: actions)
        try KnowledgeCorpus(store: store, knowledgeRoot: root, vaultURL: vault).indexMeeting(committed)

        let vaultFile = vault.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: vaultFile.path) {
            ok("vault commit \(rel)")
        } else {
            fail("vault file missing \(rel)")
        }

        let hits = try LocalRetrieve.retrieve(query: "유니크독푸드토큰XYZ", store: store, topK: 8)
        if hits.contains(where: {
            $0.unitId.contains(dogfoodId) || $0.snippet.contains("유니크독푸드") || $0.snippet.contains("결제 API")
        }) {
            ok("post-commit retrieve dogfood token hits=\(hits.count)")
        } else {
            fail("post-commit retrieve miss (hits=\(hits.map(\.unitId)))")
        }

        // useLlama false for deterministic dogfood speed (no 7B cold-load hang).
        // Retrieve quality is what we assert; generation engine may be extractive.
        let ans = try KnowledgeRAG.ask(
            question: "결제 API 스펙 결정 내용",
            store: store,
            knowledgeRoot: root,
            topK: 6,
            useLlama: false
        )
        if ans.citations.isEmpty {
            fail("rag citations empty engine=\(ans.engine)")
        } else {
            ok("rag ask engine=\(ans.engine) cites=\(ans.citations.count) ans_len=\(ans.answer.count)")
        }
    } else if doCommit {
        fail("commit skipped: status=\(m.status.rawValue)")
    }
}

let drift = try DriftChecker.run(store: store, knowledgeRoot: root, vaultURL: vault)
ok("drift \(drift.message)")

if RedactionPreflight.scan("safe meeting notes").allowed {
    ok("redaction allows clean")
} else {
    fail("redaction blocked clean")
}
if !RedactionPreflight.scan("AKIAIOSFODNN7EXAMPLE").allowed {
    ok("redaction blocks aws key")
} else {
    fail("redaction missed aws key")
}

print("== dogfood \(failures.isEmpty ? "PASS" : "FAIL") failures=\(failures.count) ==")
for f in failures { print("  - \(f)") }
exit(failures.isEmpty ? 0 : 1)
