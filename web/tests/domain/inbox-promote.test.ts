import { describe, it, expect, vi, beforeEach } from "vitest";

// tests/domain/settings.test.ts와 동일한 패턴의 thenable 쿼리 빌더 mock.
let items: Record<string, unknown>[] = [];
let events: Record<string, unknown>[] = [];

function makeQueryBuilder(table: "inbox_item" | "state_event", op: "select" | "insert" | "update", payload?: Record<string, unknown>) {
  const state: { eq?: [string, unknown] } = {};

  function exec(): Promise<{ data: unknown; error: null }> {
    const rows = table === "inbox_item" ? items : events;
    if (op === "select") {
      let result = rows.slice();
      if (state.eq) result = result.filter((r) => r[state.eq![0]] === state.eq![1]);
      // 실제 Supabase 응답처럼 스냅샷 복사본을 반환한다(참조 공유로 인한
      // 오탐 방지 — 이후 update()가 원본 row를 바꿔도 이미 반환된 값은 불변).
      return Promise.resolve({ data: result.map((r) => ({ ...r })), error: null });
    }
    if (op === "insert") {
      const row = { ...payload };
      rows.push(row);
      return Promise.resolve({ data: [{ ...row }], error: null });
    }
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
  from(table: "inbox_item" | "state_event") {
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

const { promoteInboxItem, reclaimStaleInboxItems } = await import("@/lib/db/inbox");
const { DEFAULT_HEARTBEAT_GRACE_SECONDS, DEFAULT_MAX_ATTEMPTS } = await import("@/lib/domain/state-machine");

function seedItem(overrides: Record<string, unknown>) {
  const row = { id: "item-1", ts: new Date().toISOString(), text: "hello", status: "open", attempts: 0, promoted_path: null, ...overrides };
  items.push(row);
  return row;
}

beforeEach(() => {
  items = [];
  events = [];
});

describe("promoteInboxItem", () => {
  it("성공: open -> promoting -> promoted, 가짜 커밋 함수로 GitHub 없이 검증", async () => {
    seedItem({});
    const commit = vi.fn(async () => ({ ok: true as const, path: "10 📥 수집함/item-1.md" }));

    const result = await promoteInboxItem("item-1", commit);

    expect(commit).toHaveBeenCalledTimes(1);
    expect(result.status).toBe("promoted");
    expect(result.promoted_path).toBe("10 📥 수집함/item-1.md");
    expect(items[0]).toMatchObject({ status: "promoted", attempts: 1 });
    expect(events.map((e) => `${e.from_status}->${e.to_status}`)).toEqual(["open->promoting", "promoting->promoted"]);
  });

  it("실패: 커밋 함수가 실패를 반환하면 promote_failed로 전이하고 error_code를 남긴다", async () => {
    seedItem({});
    const commit = vi.fn(async () => ({ ok: false as const, errorCode: "vault_token_missing" }));

    const result = await promoteInboxItem("item-1", commit);

    expect(result.status).toBe("promote_failed");
    expect(items[0]).toMatchObject({ status: "promote_failed", error_code: "vault_token_missing", attempts: 1 });
    expect(events.at(-1)).toMatchObject({ to_status: "promote_failed", error_code: "vault_token_missing" });
  });

  it("재시도: promote_failed(attempts<상한) 상태에서 재승격 가능하다", async () => {
    seedItem({ status: "promote_failed", attempts: 1, error_code: "boom" });
    const commit = vi.fn(async () => ({ ok: true as const, path: "10 📥 수집함/item-1.md" }));

    const result = await promoteInboxItem("item-1", commit);

    expect(result.status).toBe("promoted");
    expect(items[0]).toMatchObject({ attempts: 2 });
  });

  it("attempts 상한 도달한 promote_failed는 재승격을 거부한다", async () => {
    seedItem({ status: "promote_failed", attempts: DEFAULT_MAX_ATTEMPTS });
    await expect(promoteInboxItem("item-1", vi.fn())).rejects.toThrow(/max attempts/);
  });

  it("이미 promoted인 항목은 재승격을 거부한다(default-deny: promoted -> promoting 미선언)", async () => {
    seedItem({ status: "promoted" });
    await expect(promoteInboxItem("item-1", vi.fn())).rejects.toThrow(/illegal transition/);
  });
});

describe("reclaimStaleInboxItems (R2′/R3′)", () => {
  it("promoting + heartbeat 만료 + vault 경로 존재 → promoted로 회수(커밋 직후 죽음)", async () => {
    seedItem({
      status: "promoting",
      attempts: 0,
      heartbeat_at: new Date(Date.now() - (DEFAULT_HEARTBEAT_GRACE_SECONDS + 10) * 1000).toISOString(),
    });
    const checkPath = vi.fn(async () => true);

    const reclaimed = await reclaimStaleInboxItems(checkPath);

    expect(reclaimed).toBe(1);
    expect(items[0]).toMatchObject({ status: "promoted" });
    expect(events.at(-1)).toMatchObject({ to_status: "promoted", rule: "R2" });
  });

  it("promoting + heartbeat 만료 + vault 경로 없음 → promote_failed로 회수", async () => {
    seedItem({
      status: "promoting",
      attempts: 0,
      heartbeat_at: new Date(Date.now() - (DEFAULT_HEARTBEAT_GRACE_SECONDS + 10) * 1000).toISOString(),
    });
    const checkPath = vi.fn(async () => false);

    await reclaimStaleInboxItems(checkPath);

    expect(items[0]).toMatchObject({ status: "promote_failed" });
    expect(events.at(-1)).toMatchObject({ to_status: "promote_failed", rule: "R2" });
  });

  it("attempts 상한 도달 → vault 확인 없이 promote_failed 고정(R3′)", async () => {
    seedItem({
      status: "promoting",
      attempts: DEFAULT_MAX_ATTEMPTS,
      heartbeat_at: new Date(Date.now() - (DEFAULT_HEARTBEAT_GRACE_SECONDS + 10) * 1000).toISOString(),
    });
    const checkPath = vi.fn(async () => true);

    await reclaimStaleInboxItems(checkPath);

    expect(checkPath).not.toHaveBeenCalled();
    expect(items[0]).toMatchObject({ status: "promote_failed" });
    expect(events.at(-1)).toMatchObject({ rule: "R3" });
  });

  it("heartbeat가 유효한 promoting 항목은 건드리지 않는다", async () => {
    seedItem({ status: "promoting", attempts: 0, heartbeat_at: new Date().toISOString() });
    const reclaimed = await reclaimStaleInboxItems(vi.fn(async () => true));
    expect(reclaimed).toBe(0);
    expect(items[0]).toMatchObject({ status: "promoting" });
  });
});
