// P1-3: 백업 SQLite → Supabase 데이터 마이그레이션
// docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-3
//
// 입력은 읽기전용 백업본만 읽는다 (라이브 DB 금지, P0-2 산출물).
//
// ★ 실측 발견 (P1 실행 중): Supabase 무료 티어 프로젝트의 직접 Postgres 연결
// (db.<ref>.supabase.co:5432)은 AAAA 레코드만 존재하고(IPv6 전용), 이 실행
// 환경은 IPv6 아웃바운드 라우트가 없어 EHOSTUNREACH로 접속이 불가능했다.
// → 대응: 원시 Postgres 프로토콜(5432) 대신 PostgREST(HTTPS, IPv4 가능)로
// upsert한다. RLS는 P1 시점에 아직 꺼져 있어 anon 키로도 전체 테이블 쓰기가
// 가능하다(P3에서 RLS 활성화 후에는 이 경로가 막히므로 재사용 불가 — 일회성
// 마이그레이션 전용 스크립트).
//
// 멱등: PostgREST `Prefer: resolution=merge-duplicates` + `on_conflict`로
// on-conflict-do-update와 동일하게 동작. 여러 번 재실행 가능해야 한다 (G1-2).
//
// 스코프 밖 (docs/REFACTOR_BACKLOG.md 참조): P0-8 드리프트로 생긴 unit 1건 +
// 원래 미인덱스였던 vault 파일 4건은 백업 SQLite에 존재하지 않아 이 스크립트로
// 이관할 수 없다. P4a 인제스트 구현 시 함께 처리한다.
//
// owner_id: P3 인증 도입 전이라 실제 auth.uid()가 없다. 고정 placeholder UUID를
// 쓰고, P3에서 실제 사용자가 생기면 UPDATE 1건으로 교체한다 (docs/ENV_VARS.md 참조).

import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import Database from "better-sqlite3";

const OWNER_ID = "00000000-0000-0000-0000-000000000001";
const BACKUP_ROOT = path.join(process.env.HOME || "", "Knowledge-backup-2026-07-27");
const SQLITE_PATH = path.join(BACKUP_ROOT, "knowledge.db");
const DIET_JSON_PATH = path.join(BACKUP_ROOT, "services/diet/diet.json");
const INBOX_JSON_PATH = path.join(BACKUP_ROOT, "services/inbox/inbox.json");
const FEATURES_JSON_PATH = path.join(BACKUP_ROOT, "config/features.json");
const APP_JSON_PATH = path.join(BACKUP_ROOT, "config/app.json");

// NEXT_PUBLIC_* 값과 동일 — 클라이언트 번들에 들어가는 공개 값이라 여기 상수로
// 둬도 안전하다 (서비스 롤 키가 아님). 출처: mcp__supabase__get_project_url /
// get_publishable_keys. web/.env.local의 NEXT_PUBLIC_* 자리도 채워둘 것(P4a).
const SUPABASE_URL = "https://gppklwzcmfuuhsefdeik.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdwcGtsd3pjbWZ1dWhzZWZkZWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxMzcyNTcsImV4cCI6MjEwMDcxMzI1N30.pQ9gmWSZdMfIqkbunwffgEj-cOTUZKBalq7KIW8smjA";

// features.json 이관 대상 키 (그 외는 로컬/미팅 전용이라 제외 — §P1-3)
const FEATURES_INCLUDE = ["cloud_llm", "notes_ingest"];
// vector_search는 값과 무관하게 false로 강제 (C-7: chunk_vector 미이관)
const FEATURES_FORCE_FALSE = ["vector_search"];

function toBool(v: number): boolean {
  return v === 1;
}

async function upsert(table: string, onConflict: string, rows: Record<string, unknown>[]) {
  if (rows.length === 0) return;
  const batchSize = 300;
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);
    const url = `${SUPABASE_URL}/rest/v1/${table}?on_conflict=${encodeURIComponent(onConflict)}`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${ANON_KEY}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(batch),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`upsert ${table} failed: ${res.status} ${text}`);
    }
  }
}

async function main() {
  if (!fs.existsSync(SQLITE_PATH)) {
    throw new Error(`backup sqlite not found: ${SQLITE_PATH}`);
  }

  // 백업 파일은 chmod a-w 잠금 상태(P0-2)이고 WAL 모드라, 읽기전용으로 직접 열어도
  // -wal/-shm 생성을 시도해 실패한다. 잠긴 원본은 절대 건드리지 않고, 임시 사본을
  // 열어서 읽는다 (원본 무결성 유지).
  const tmpCopy = path.join(os.tmpdir(), `knowledge-backup-readonly-${Date.now()}.db`);
  fs.copyFileSync(SQLITE_PATH, tmpCopy);
  const sqlite = new Database(tmpCopy, { readonly: true, fileMustExist: true });
  const report: Record<string, number> = {};

  try {
    // connected_source (meeting 제외 — F-1)
    const sources = sqlite
      .prepare(`select * from connected_source where source_type != 'meeting'`)
      .all() as any[];
    await upsert(
      "connected_source",
      "id",
      sources.map((s) => ({
        id: s.id, owner_id: OWNER_ID, source_type: s.source_type, root_path: s.root_path,
        label: s.label, enabled: toBool(s.enabled), last_sync_at: s.last_sync_at,
        last_error: s.last_error, unit_count: s.unit_count, created_at: s.created_at, updated_at: s.updated_at,
      }))
    );
    report.connected_source = sources.length;

    // knowledge_unit (Meetings/ 접두 제외 — F-1)
    const units = sqlite
      .prepare(`select * from knowledge_unit where sot_ref not like 'Meetings/%'`)
      .all() as any[];
    await upsert(
      "knowledge_unit",
      "unit_id",
      units.map((u) => ({
        unit_id: u.unit_id, owner_id: OWNER_ID, source_type: u.source_type, title: u.title,
        scope: u.scope, sot_kind: u.sot_kind, sot_ref: u.sot_ref, content_hash: u.content_hash,
        in_corpus: toBool(u.in_corpus), rag_eligible: toBool(u.rag_eligible), updated_at: u.updated_at,
      }))
    );
    report.knowledge_unit = units.length;
    const keptUnitIds = new Set(units.map((u) => u.unit_id as string));

    // knowledge_chunk (제외된 unit 연쇄 필터)
    const chunks = (sqlite.prepare(`select * from knowledge_chunk`).all() as any[]).filter((c) =>
      keptUnitIds.has(c.unit_id)
    );
    await upsert(
      "knowledge_chunk",
      "chunk_id",
      chunks.map((c) => ({
        chunk_id: c.chunk_id, owner_id: OWNER_ID, unit_id: c.unit_id, ordinal: c.ordinal,
        text: c.text, content_hash: c.content_hash,
      }))
    );
    report.knowledge_chunk = chunks.length;

    // note_mirror (미팅 무관, 전량)
    const notes = sqlite.prepare(`select * from note_mirror`).all() as any[];
    await upsert(
      "note_mirror",
      "notes_id",
      notes.map((n) => ({
        notes_id: n.notes_id, owner_id: OWNER_ID, folder: n.folder, title: n.title,
        body_text: n.body_text, content_hash: n.content_hash, body_status: n.body_status,
        mirror_not_sot: toBool(n.mirror_not_sot), updated_at: n.updated_at,
      }))
    );
    report.note_mirror = notes.length;

    // source_pointer (제외된 unit을 가리키는 vault_rel_path 행 제외)
    const excludedRefs = new Set(
      (sqlite.prepare(`select sot_ref from knowledge_unit where sot_ref like 'Meetings/%'`).all() as any[]).map(
        (r) => r.sot_ref
      )
    );
    const pointers = (sqlite.prepare(`select * from source_pointer`).all() as any[]).filter(
      (p) => !(p.vault_rel_path && excludedRefs.has(p.vault_rel_path))
    );
    await upsert(
      "source_pointer",
      "id",
      pointers.map((p) => ({
        id: p.id, owner_id: OWNER_ID, source_type: p.source_type, external_id: p.external_id,
        title: p.title, scope: p.scope, notes_id: p.notes_id, vault_rel_path: p.vault_rel_path,
        updated_at: p.updated_at,
      }))
    );
    report.source_pointer = pointers.length;

    // fts_docs → search_doc (제외된 unit 필터, doc_id=unit_id 1:1 확인됨)
    const ftsDocs = (sqlite.prepare(`select * from fts_docs`).all() as any[]).filter((d) =>
      keptUnitIds.has(d.doc_id)
    );
    await upsert(
      "search_doc",
      "doc_id",
      ftsDocs.map((d) => ({
        doc_id: d.doc_id, owner_id: OWNER_ID, source_type: d.source_type, title: d.title, body: d.body,
      }))
    );
    report.search_doc = ftsDocs.length;

    // diet.json → diet_meal / diet_workout / diet_metric + settings
    const diet = JSON.parse(fs.readFileSync(DIET_JSON_PATH, "utf8"));
    const meals = diet.meals ?? [];
    await upsert(
      "diet_meal",
      "id",
      meals.map((m: any) => ({
        id: m.id, owner_id: OWNER_ID, ts: m.ts, note: m.note ?? null, items: m.items ?? [],
        kcal: m.kcal ?? null, protein_g: m.protein_g ?? null,
      }))
    );
    report.diet_meal = meals.length;

    const workouts = diet.workouts ?? [];
    await upsert(
      "diet_workout",
      "id",
      workouts.map((w: any) => ({
        id: w.id, owner_id: OWNER_ID, ts: w.ts, kind: w.kind ?? null, minutes: w.minutes ?? null,
        intensity: w.intensity ?? null,
      }))
    );
    report.diet_workout = workouts.length;

    const metrics = diet.metrics ?? [];
    await upsert(
      "diet_metric",
      "id",
      metrics.map((m: any) => ({
        id: m.id, owner_id: OWNER_ID, ts: m.ts, weight_kg: m.weight_kg ?? null, sleep_h: m.sleep_h ?? null,
      }))
    );
    report.diet_metric = metrics.length;

    // settings: diet.goals/profile + features/app 선별 키 + search.mode 기본값
    const settingsRows: Record<string, unknown>[] = [];
    function addSetting(key: string, value: unknown) {
      settingsRows.push({ owner_id: OWNER_ID, key, value, updated_at: new Date().toISOString() });
    }
    if (diet.goals) addSetting("diet.goals", diet.goals);
    if (diet.profile) addSetting("diet.profile", diet.profile);

    const features = JSON.parse(fs.readFileSync(FEATURES_JSON_PATH, "utf8"));
    for (const key of FEATURES_INCLUDE) {
      if (key in features) addSetting(`feature.${key}`, features[key]);
    }
    for (const key of FEATURES_FORCE_FALSE) {
      addSetting(`feature.${key}`, false);
    }

    const app = JSON.parse(fs.readFileSync(APP_JSON_PATH, "utf8"));
    if (app.notes?.page_size !== undefined) addSetting("app.notes.page_size", app.notes.page_size);
    if (app.rag !== undefined) addSetting("app.rag", app.rag);
    // search.mode 기본값 명시 (D-4: P1에서는 tsvector 외 값을 기본으로 두지 않음)
    addSetting("search.mode", "tsvector");

    await upsert("settings", "owner_id,key", settingsRows);
    report.settings = settingsRows.length;

    // inbox.json → inbox_item
    const inbox = JSON.parse(fs.readFileSync(INBOX_JSON_PATH, "utf8"));
    const inboxItems = inbox.items ?? [];
    await upsert(
      "inbox_item",
      "id",
      inboxItems.map((item: any) => ({
        id: item.id, owner_id: OWNER_ID, ts: item.ts, text: item.text, status: item.status,
        promoted_path: item.promotedPath ?? null, updated_at: item.ts,
      }))
    );
    report.inbox_item = inboxItems.length;

    console.log("=== migrate-from-sqlite report ===");
    for (const [table, count] of Object.entries(report)) {
      console.log(`${table.padEnd(20)} ${count}`);
    }
  } finally {
    sqlite.close();
    fs.rmSync(tmpCopy, { force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
