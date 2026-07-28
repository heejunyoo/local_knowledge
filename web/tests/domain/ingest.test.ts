import { describe, it, expect, vi, beforeEach } from "vitest";

// tests/domain/settings.test.ts와 동일한 패턴: createClient()를 얇은 thenable
// 쿼리 빌더로 mock한다. select/insert/update가 전부 이 빌더 하나로 처리된다.
let jobs: Record<string, unknown>[] = [];
let events: Record<string, unknown>[] = [];
let jobSeq = 0;

function makeQueryBuilder(table: "ingest_job" | "state_event", op: "select" | "insert" | "update", payload?: Record<string, unknown>) {
  const state: { eq?: [string, unknown]; order?: boolean; limit?: number } = {};

  function exec(): Promise<{ data: unknown; error: null }> {
    const rows = table === "ingest_job" ? jobs : events;
    if (op === "select") {
      let result = rows.slice();
      if (state.eq) result = result.filter((r) => r[state.eq![0]] === state.eq![1]);
      if (state.order) result = result.sort((a, b) => (b.created_at as number) - (a.created_at as number));
      if (state.limit != null) result = result.slice(0, state.limit);
      // 실제 Supabase 응답처럼 스냅샷 복사본을 반환한다 — 이후 update()가
      // jobs 배열의 원본 row를 바꿔도 이미 반환된 참조는 영향받지 않아야 한다.
      return Promise.resolve({ data: result.map((r) => ({ ...r })), error: null });
    }
    if (op === "insert") {
      const row =
        table === "ingest_job"
          ? { id: `job-${++jobSeq}`, attempts: 0, status: "queued", created_at: Date.now(), ...payload }
          : { ...payload };
      rows.push(row);
      return Promise.resolve({ data: [{ ...row }], error: null });
    }
    // update
    if (state.eq) {
      rows.filter((r) => r[state.eq![0]] === state.eq![1]).forEach((r) => Object.assign(r, payload));
    }
    return Promise.resolve({ data: null, error: null });
  }

  const builder: Record<string, unknown> = {
    eq(col: string, val: unknown) {
      state.eq = [col, val];
      return builder;
    },
    order() {
      state.order = true;
      return builder;
    },
    limit(n: number) {
      state.limit = n;
      return builder;
    },
    select() {
      return builder;
    },
    single() {
      return exec().then((r) => ({ data: (r.data as unknown[])?.[0] ?? null, error: r.error }));
    },
    then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
      return exec().then(resolve, reject);
    },
  };
  return builder;
}

const supabaseMock = {
  auth: { getClaims: () => Promise.resolve({ data: { claims: { sub: "owner-1" } } }) },
  from(table: "ingest_job" | "state_event") {
    return {
      select: () => makeQueryBuilder(table, "select"),
      insert: (payload: Record<string, unknown>) => makeQueryBuilder(table, "insert", payload),
      update: (payload: Record<string, unknown>) => makeQueryBuilder(table, "update", payload),
    };
  },
};

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => supabaseMock),
}));

const { runIngestJob, reclaimStaleIngestJobs } = await import("@/lib/db/ingest");
const { DEFAULT_HEARTBEAT_GRACE_SECONDS, DEFAULT_MAX_ATTEMPTS } = await import("@/lib/domain/state-machine");

function findJob(kind: string) {
  return jobs.find((j) => j.kind === kind);
}

beforeEach(() => {
  jobs = [];
  events = [];
  jobSeq = 0;
});

describe("runIngestJob", () => {
  it("성공: queued 신규 생성 → running → done, state_event 2건 기록", async () => {
    const worker = vi.fn(async () => ({ ok: true as const, detail: { inserted: 3 } }));
    const result = await runIngestJob("search_reindex", worker);

    expect(result.status).toBe("done");
    expect(worker).toHaveBeenCalledTimes(1);
    const job = findJob("search_reindex");
    expect(job).toMatchObject({ status: "done", attempts: 1 });
    expect(events.map((e) => `${e.from_status}->${e.to_status}`)).toEqual(["queued->running", "running->done"]);
  });

  it("실패: worker가 {ok:false}를 반환하면 failed로 전이하고 error_code를 남긴다", async () => {
    const worker = vi.fn(async () => ({ ok: false as const, errorCode: "boom" }));
    const result = await runIngestJob("corpus_sync", worker);

    expect(result.status).toBe("failed");
    expect(result.error_code).toBe("boom");
    const job = findJob("corpus_sync");
    expect(job).toMatchObject({ status: "failed", error_code: "boom", attempts: 1 });
  });

  it("실패: worker가 throw해도 failed로 전이한다(런타임 에러를 상태기계가 흡수)", async () => {
    const worker = vi.fn(async () => {
      throw new Error("kaboom");
    });
    const result = await runIngestJob("corpus_sync", worker);
    expect(result.status).toBe("failed");
    expect(result.error_code).toBe("kaboom");
  });

  it("재큐잉 성공(G4a-4): failed(attempts<상한) 재호출 시 같은 row를 failed→queued→running→done으로 재사용한다", async () => {
    jobs.push({
      id: "job-existing",
      kind: "search_reindex",
      status: "failed",
      attempts: 1,
      created_at: Date.now(),
    });

    const worker = vi.fn(async () => ({ ok: true as const, detail: {} }));
    const result = await runIngestJob("search_reindex", worker);

    expect(result.id).toBe("job-existing");
    expect(result.status).toBe("done");
    const job = findJob("search_reindex");
    expect(job).toMatchObject({ id: "job-existing", status: "done", attempts: 2 });
    expect(events.map((e) => `${e.from_status}->${e.to_status}`)).toEqual([
      "failed->queued",
      "queued->running",
      "running->done",
    ]);
  });

  it("attempts 상한 도달한 failed는 재큐잉을 거부한다(자동 재시도 없음)", async () => {
    jobs.push({
      id: "job-maxed",
      kind: "search_reindex",
      status: "failed",
      attempts: DEFAULT_MAX_ATTEMPTS,
      created_at: Date.now(),
    });

    await expect(runIngestJob("search_reindex", vi.fn())).rejects.toThrow(/max attempts/);
  });

  it("이미 running인 job은 재시작을 거부한다(workerFree 가드)", async () => {
    jobs.push({ id: "job-running", kind: "corpus_sync", status: "running", attempts: 0, created_at: Date.now() });
    await expect(runIngestJob("corpus_sync", vi.fn())).rejects.toThrow(/already running/);
  });
});

describe("reclaimStaleIngestJobs (R2″/R3)", () => {
  it("running + heartbeat 만료 → failed로 회수하고 state_event에 rule R2를 남긴다", async () => {
    jobs.push({
      id: "job-stale",
      kind: "corpus_sync",
      status: "running",
      attempts: 0,
      heartbeat_at: new Date(Date.now() - (DEFAULT_HEARTBEAT_GRACE_SECONDS + 10) * 1000).toISOString(),
    });

    const reclaimed = await reclaimStaleIngestJobs();

    expect(reclaimed).toBe(1);
    expect(findJob("corpus_sync")).toMatchObject({ status: "failed", error_code: "heartbeat_timeout" });
    expect(events).toContainEqual(
      expect.objectContaining({ subject_id: "job-stale", from_status: "running", to_status: "failed", rule: "R2" }),
    );
  });

  it("attempts 상한 도달한 채로 회수되면 rule R3로 구분해 기록한다", async () => {
    jobs.push({
      id: "job-stale-maxed",
      kind: "corpus_sync",
      status: "running",
      attempts: DEFAULT_MAX_ATTEMPTS,
      heartbeat_at: new Date(Date.now() - (DEFAULT_HEARTBEAT_GRACE_SECONDS + 10) * 1000).toISOString(),
    });

    await reclaimStaleIngestJobs();

    expect(events).toContainEqual(expect.objectContaining({ subject_id: "job-stale-maxed", rule: "R3" }));
  });

  it("heartbeat가 아직 유효한 running job은 건드리지 않는다", async () => {
    jobs.push({
      id: "job-fresh",
      kind: "corpus_sync",
      status: "running",
      attempts: 0,
      heartbeat_at: new Date().toISOString(),
    });

    const reclaimed = await reclaimStaleIngestJobs();

    expect(reclaimed).toBe(0);
    expect(findJob("corpus_sync")).toMatchObject({ status: "running" });
  });
});
