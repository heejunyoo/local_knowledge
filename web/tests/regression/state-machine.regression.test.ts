// G4a-3/G4a-4: 실 Supabase 프로젝트에 대한 상태기계 왕복 검증.
// 실행: npm run test:regression (web/.env.local 필요).
//
// G4a-2(inbox.promote의 실제 vault Git 커밋 왕복)는 VAULT_GITHUB_TOKEN
// 미발급으로 이 세션 범위 밖이다(REFACTOR_STATUS.md) — 대신 토큰이 없을 때
// defaultVaultCommit이 안전하게 promote_failed로 떨어지는 실제 경로만 검증한다.
import { describe, it, expect, vi } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { runIngestJob, reclaimStaleIngestJobs } = await import("@/lib/db/ingest");
const { promoteInboxItem } = await import("@/lib/db/inbox");

describe("G4a-4: ingest_job 고아 회수 → 재큐잉 (실 DB)", () => {
  it("running + heartbeat 만료 orphan을 failed로 회수한 뒤, 재호출 시 같은 kind가 재큐잉되어 완료된다", async () => {
    const supabase = await testSupabaseClient();
    const { data: owner } = await supabase.auth.getClaims();
    const ownerId = owner!.claims.sub;

    const { data: orphan, error: insertError } = await supabase
      .from("ingest_job")
      .insert({
        owner_id: ownerId,
        kind: "search_reindex",
        status: "running",
        attempts: 0,
        heartbeat_at: new Date(Date.now() - 999_000).toISOString(),
      })
      .select("id")
      .single();
    expect(insertError).toBeNull();

    const reclaimed = await reclaimStaleIngestJobs();
    expect(reclaimed).toBeGreaterThanOrEqual(1);

    const { data: afterReclaim } = await supabase
      .from("ingest_job")
      .select("status,error_code")
      .eq("id", orphan!.id)
      .single();
    expect(afterReclaim).toMatchObject({ status: "failed", error_code: "heartbeat_timeout" });

    const result = await runIngestJob("search_reindex");
    expect(result.status).toBe("done");

    const { data: final } = await supabase
      .from("ingest_job")
      .select("id,status,attempts")
      .eq("id", orphan!.id)
      .single();
    expect(final).toMatchObject({ id: orphan!.id, status: "done", attempts: 1 });

    const { data: trail } = await supabase
      .from("state_event")
      .select("from_status,to_status,rule")
      .eq("subject_kind", "ingest_job")
      .eq("subject_id", orphan!.id)
      .order("ts", { ascending: true });
    expect(trail?.map((e) => `${e.from_status}->${e.to_status}`)).toEqual([
      "running->failed",
      "failed->queued",
      "queued->running",
      "running->done",
    ]);
  });

  it("corpus.sync 워커가 connected_source.unit_count를 실제 집계로 갱신한다", async () => {
    const result = await runIngestJob("corpus_sync");
    expect(result.status).toBe("done");
    expect(result.detail).toMatchObject({ updated: expect.any(Number) });
  });
});

describe("G4a-3: inbox.promote 실 DB 경로 (VAULT_GITHUB_TOKEN 미발급 상태)", () => {
  it("토큰이 없으면 defaultVaultCommit이 안전하게 promote_failed로 떨어진다", async () => {
    const supabase = await testSupabaseClient();
    const { data: owner } = await supabase.auth.getClaims();
    const ownerId = owner!.claims.sub;

    const { data: item, error: insertError } = await supabase
      .from("inbox_item")
      .insert({ owner_id: ownerId, text: "[state-machine.regression.test.ts] 임시 항목" })
      .select("id")
      .single();
    expect(insertError).toBeNull();

    try {
      const result = await promoteInboxItem(item!.id);
      expect(result.status).toBe("promote_failed");

      const { data: events } = await supabase
        .from("state_event")
        .select("from_status,to_status,error_code")
        .eq("subject_kind", "inbox_item")
        .eq("subject_id", item!.id)
        .order("ts", { ascending: true });
      expect(events?.map((e) => `${e.from_status}->${e.to_status}`)).toEqual([
        "open->promoting",
        "promoting->promote_failed",
      ]);
      expect(events?.at(-1)).toMatchObject({ error_code: "vault_token_missing" });
    } finally {
      // 실 오너 인박스 목록을 어지럽히지 않도록 테스트 항목을 정리한다.
      await supabase.from("state_event").delete().eq("subject_kind", "inbox_item").eq("subject_id", item!.id);
      await supabase.from("inbox_item").delete().eq("id", item!.id);
    }
  });
});
