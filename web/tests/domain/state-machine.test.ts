import { describe, it, expect } from "vitest";
import {
  canTransition,
  INBOX_TRANSITIONS,
  INGEST_TRANSITIONS,
  recoverInboxItem,
  recoverIngestJob,
  DEFAULT_MAX_ATTEMPTS,
  DEFAULT_HEARTBEAT_GRACE_SECONDS,
  type InboxStatus,
  type IngestStatus,
} from "@/lib/domain/state-machine";

const INBOX_STATES: InboxStatus[] = ["open", "promoting", "promoted", "promote_failed"];
const INGEST_STATES: IngestStatus[] = ["queued", "running", "done", "failed"];

function allPairs<S extends string>(states: S[]): [S, S][] {
  const pairs: [S, S][] = [];
  for (const from of states) for (const to of states) pairs.push([from, to]);
  return pairs;
}

describe("default-deny: inbox_item", () => {
  it("모든 선언된 전이는 허용된다", () => {
    for (const t of INBOX_TRANSITIONS) {
      expect(canTransition(INBOX_TRANSITIONS, t.from, t.to)).toBe(true);
    }
  });

  it("선언되지 않은 전이는 전부 거부된다 (default-deny)", () => {
    const illegal = allPairs(INBOX_STATES).filter(
      ([from, to]) => !INBOX_TRANSITIONS.some((t) => t.from === from && t.to === to),
    );
    expect(illegal.length).toBeGreaterThanOrEqual(10);
    for (const [from, to] of illegal) {
      expect(canTransition(INBOX_TRANSITIONS, from, to)).toBe(false);
    }
  });

  it("S11: open -> promoted 직행(와일드카드)은 거부된다 — promoted 진입은 promoting에서만", () => {
    expect(canTransition(INBOX_TRANSITIONS, "open", "promoted")).toBe(false);
    expect(canTransition(INBOX_TRANSITIONS, "promote_failed", "promoted")).toBe(false);
  });
});

describe("default-deny: ingest_job", () => {
  it("모든 선언된 전이는 허용된다", () => {
    for (const t of INGEST_TRANSITIONS) {
      expect(canTransition(INGEST_TRANSITIONS, t.from, t.to)).toBe(true);
    }
  });

  it("선언되지 않은 전이는 전부 거부된다 (default-deny)", () => {
    const illegal = allPairs(INGEST_STATES).filter(
      ([from, to]) => !INGEST_TRANSITIONS.some((t) => t.from === from && t.to === to),
    );
    expect(illegal.length).toBeGreaterThanOrEqual(10);
    for (const [from, to] of illegal) {
      expect(canTransition(INGEST_TRANSITIONS, from, to)).toBe(false);
    }
  });

  it("와일드카드 직행(queued -> done)은 거부된다 — running을 반드시 거쳐야 한다", () => {
    expect(canTransition(INGEST_TRANSITIONS, "queued", "done")).toBe(false);
    expect(canTransition(INGEST_TRANSITIONS, "queued", "failed")).toBe(false);
  });
});

describe("R2′/R3′: recoverInboxItem", () => {
  it("promoting이 아니면 회수 대상이 아니다", () => {
    expect(
      recoverInboxItem({ status: "open", heartbeatAgeSeconds: 999, attempts: 0, vaultPathExists: false }),
    ).toBeNull();
  });

  it("heartbeat가 만료되지 않았으면 회수하지 않는다", () => {
    expect(
      recoverInboxItem({
        status: "promoting",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS - 1,
        attempts: 0,
        vaultPathExists: true,
      }),
    ).toBeNull();
  });

  it("R2′: heartbeat 만료 + vault 경로 존재 → promoted로 회수(커밋 직후 죽음)", () => {
    expect(
      recoverInboxItem({
        status: "promoting",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS,
        attempts: 0,
        vaultPathExists: true,
      }),
    ).toEqual({ rule: "R2", to: "promoted" });
  });

  it("R2′: heartbeat 만료 + vault 경로 없음 → promote_failed로 회수", () => {
    expect(
      recoverInboxItem({
        status: "promoting",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS,
        attempts: 0,
        vaultPathExists: false,
      }),
    ).toEqual({ rule: "R2", to: "promote_failed" });
  });

  it("R3′: attempts 상한 도달 → vault 경로와 무관하게 promote_failed 고정(자동 재시도 없음)", () => {
    expect(
      recoverInboxItem({
        status: "promoting",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS,
        attempts: DEFAULT_MAX_ATTEMPTS,
        vaultPathExists: true,
      }),
    ).toEqual({ rule: "R3", to: "promote_failed" });
  });
});

describe("R2″: recoverIngestJob", () => {
  it("running이 아니면 회수 대상이 아니다", () => {
    expect(recoverIngestJob({ status: "queued", heartbeatAgeSeconds: 999, attempts: 0 })).toBeNull();
  });

  it("heartbeat가 만료되지 않았으면 회수하지 않는다", () => {
    expect(
      recoverIngestJob({
        status: "running",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS - 1,
        attempts: 0,
      }),
    ).toBeNull();
  });

  it("R2″: running + heartbeat 만료 → failed로 강제 회수", () => {
    expect(
      recoverIngestJob({ status: "running", heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS, attempts: 0 }),
    ).toEqual({ rule: "R2", to: "failed" });
  });

  it("R3: attempts 상한 도달 시에도 failed지만 규칙 id로 구분된다(자동 재시도 불가 표식)", () => {
    expect(
      recoverIngestJob({
        status: "running",
        heartbeatAgeSeconds: DEFAULT_HEARTBEAT_GRACE_SECONDS,
        attempts: DEFAULT_MAX_ATTEMPTS,
      }),
    ).toEqual({ rule: "R3", to: "failed" });
  });
});
