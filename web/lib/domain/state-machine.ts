// D-3 확정: default-deny 상태기계 (액션플랜 §P4a 작업 단계 4).
// 원본 PipelineGraph.swift(합법 엣지를 데이터로 선언, 없는 전이는 default-deny,
// 와일드카드→최종상태 금지) + CrashRecovery.swift(R1-R6 고아 회수)의 구조를
// 그대로 옮기되 inbox_item/ingest_job 두 도메인의 상태 집합으로 교체한다.

export interface Transition<S extends string> {
  from: S;
  to: S;
  guard: string;
}

/** default-deny: transitions 배열에 없는 (from,to)는 무조건 거부. */
export function canTransition<S extends string>(
  transitions: readonly Transition<S>[],
  from: S,
  to: S,
): boolean {
  return transitions.some((t) => t.from === from && t.to === to);
}

export function findTransition<S extends string>(
  transitions: readonly Transition<S>[],
  from: S,
  to: S,
): Transition<S> | undefined {
  return transitions.find((t) => t.from === from && t.to === to);
}

// ---------------------------------------------------------------------------
// ① inbox_item — 승격 파이프라인 (액션플랜 라인 963-970)
// ---------------------------------------------------------------------------

export type InboxStatus = "open" | "promoting" | "promoted" | "promote_failed";

export const INBOX_TRANSITIONS: readonly Transition<InboxStatus>[] = [
  { from: "open", to: "promoting", guard: "userRequest" },
  // promoted 진입은 이 엣지가 유일하다 (S11: 와일드카드→최종상태 금지 계승).
  { from: "promoting", to: "promoted", guard: "vaultCommitOk" },
  { from: "promoting", to: "promote_failed", guard: "commitError|timeout" },
  { from: "promote_failed", to: "promoting", guard: "retryUnderMaxAttempts" },
  { from: "promote_failed", to: "open", guard: "userOnly" },
];

// ---------------------------------------------------------------------------
// ② ingest_job — corpus.sync / search.reindex (액션플랜 라인 976-982)
// ---------------------------------------------------------------------------

export type IngestStatus = "queued" | "running" | "done" | "failed";

export const INGEST_TRANSITIONS: readonly Transition<IngestStatus>[] = [
  { from: "queued", to: "running", guard: "workerFree" },
  { from: "running", to: "done", guard: "completed" },
  { from: "running", to: "failed", guard: "error|timeout" },
  { from: "failed", to: "queued", guard: "retryUnderMaxAttempts" },
];

// ---------------------------------------------------------------------------
// 크래시 복구 규칙 — CrashRecovery.swift의 순수 함수 패턴 계승.
// Thresholds.default(Swift) 계승: maxStageAttempts=2, heartbeat grace=120초.
// ---------------------------------------------------------------------------

export const DEFAULT_MAX_ATTEMPTS = 2;
export const DEFAULT_HEARTBEAT_GRACE_SECONDS = 120;

export interface RecoveryOutcome<S extends string> {
  rule: "R2" | "R3";
  to: S;
}

export interface InboxRecoverySnapshot {
  status: InboxStatus;
  heartbeatAgeSeconds: number | null;
  attempts: number;
  /** promote 커밋이 실제로는 성공했는지(GitHub 경로 존재 확인 결과) — 호출부 주입. */
  vaultPathExists: boolean;
  maxAttempts?: number;
  heartbeatGraceSeconds?: number;
}

/**
 * R2′: promoting + heartbeat 만료 → 커밋 직후 죽었을 가능성 → vault 경로
 * 존재 여부로 promoted(커밋은 됐음) 또는 promote_failed(커밋 안 됨) 판정.
 * R3′: attempts가 상한 도달 → promote_failed 고정, 자동 재시도 중단(R2′보다 우선).
 * 그 외에는 회수 대상이 아니다(null).
 */
export function recoverInboxItem(
  snap: InboxRecoverySnapshot,
): RecoveryOutcome<InboxStatus> | null {
  if (snap.status !== "promoting") return null;

  const maxAttempts = snap.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const grace = snap.heartbeatGraceSeconds ?? DEFAULT_HEARTBEAT_GRACE_SECONDS;
  const heartbeatExpired = snap.heartbeatAgeSeconds != null && snap.heartbeatAgeSeconds >= grace;
  if (!heartbeatExpired) return null;

  if (snap.attempts >= maxAttempts) {
    return { rule: "R3", to: "promote_failed" };
  }
  return { rule: "R2", to: snap.vaultPathExists ? "promoted" : "promote_failed" };
}

export interface IngestRecoverySnapshot {
  status: IngestStatus;
  heartbeatAgeSeconds: number | null;
  attempts: number;
  maxAttempts?: number;
  heartbeatGraceSeconds?: number;
}

/**
 * R2″: running + heartbeat 만료 → failed로 강제 회수. attempts 상한 도달이면
 * R3(같은 failed 결과지만 규칙 id로 "자동 재시도 없음"을 구분해 기록).
 */
export function recoverIngestJob(
  snap: IngestRecoverySnapshot,
): RecoveryOutcome<IngestStatus> | null {
  if (snap.status !== "running") return null;

  const grace = snap.heartbeatGraceSeconds ?? DEFAULT_HEARTBEAT_GRACE_SECONDS;
  const heartbeatExpired = snap.heartbeatAgeSeconds != null && snap.heartbeatAgeSeconds >= grace;
  if (!heartbeatExpired) return null;

  const maxAttempts = snap.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  if (snap.attempts >= maxAttempts) {
    return { rule: "R3", to: "failed" };
  }
  return { rule: "R2", to: "failed" };
}
