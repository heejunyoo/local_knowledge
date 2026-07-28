import { createClient } from "@/lib/supabase/server";
import {
  canTransition,
  recoverIngestJob,
  DEFAULT_MAX_ATTEMPTS,
  INGEST_TRANSITIONS,
  type IngestStatus,
} from "@/lib/domain/state-machine";
import { recordStateEvent } from "@/lib/db/state-event";
import { syncConnectedSourceStats } from "@/lib/db/corpus";
import { reindexMissingSearchDocs } from "@/lib/db/search";

export type IngestKind = "corpus_sync" | "search_reindex";
export type IngestWorkerResult = { ok: true; detail: unknown } | { ok: false; errorCode: string };
export type IngestWorker = () => Promise<IngestWorkerResult>;

// PAT 없이도 실행 가능한 DB 내부 실작업 (오너 승인, REFACTOR_STATUS 참고).
// GitHub 기반 실제 vault 재수집은 PAT 발급 후 별도 task로 이관한다.
export const WORKERS: Record<IngestKind, IngestWorker> = {
  corpus_sync: async () => ({ ok: true, detail: await syncConnectedSourceStats() }),
  search_reindex: async () => ({ ok: true, detail: await reindexMissingSearchDocs() }),
};

type IngestRow = { id: string; status: IngestStatus; attempts: number };

/**
 * 같은 kind의 가장 최근 job을 재사용한다: done이면 새 row, queued면 그대로,
 * failed면 재큐잉(retryUnderMaxAttempts), running이면 workerFree 가드 실패로
 * 거부한다.
 */
async function claimJobRow(
  supabase: Awaited<ReturnType<typeof createClient>>,
  ownerId: string,
  kind: IngestKind,
): Promise<IngestRow> {
  const { data: rows, error } = await supabase
    .from("ingest_job")
    .select("id,status,attempts")
    .eq("kind", kind)
    .order("created_at", { ascending: false })
    .limit(1);
  if (error) throw error;
  const existing = rows?.[0] as IngestRow | undefined;

  if (!existing || existing.status === "done") {
    const { data: created, error: insertError } = await supabase
      .from("ingest_job")
      .insert({ owner_id: ownerId, kind, status: "queued" })
      .select("id,status,attempts")
      .single();
    if (insertError) throw insertError;
    return created as IngestRow;
  }

  if (existing.status === "queued") return existing;

  if (existing.status === "failed") {
    if (existing.attempts >= DEFAULT_MAX_ATTEMPTS) {
      throw new Error(`ingest.${kind}: max attempts reached`);
    }
    if (!canTransition(INGEST_TRANSITIONS, "failed", "queued")) {
      throw new Error(`ingest.${kind}: illegal transition failed -> queued`);
    }
    const { error: updateError } = await supabase
      .from("ingest_job")
      .update({ status: "queued", error_code: null })
      .eq("id", existing.id);
    if (updateError) throw updateError;
    await recordStateEvent({
      subjectKind: "ingest_job",
      subjectId: existing.id,
      from: "failed",
      to: "queued",
      rule: "retryUnderMaxAttempts",
    });
    return { ...existing, status: "queued" };
  }

  // running: workerFree 가드 실패 — default-deny(선언 안 된 running->running 없음).
  throw new Error(`ingest.${kind}: already running`);
}

export async function runIngestJob(
  kind: IngestKind,
  worker: IngestWorker = WORKERS[kind],
): Promise<{ id: string; status: IngestStatus; detail?: unknown; error_code?: string }> {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const ownerId = claims?.claims.sub;
  if (!ownerId) throw new Error("ingest: no authenticated user");

  const job = await claimJobRow(supabase, ownerId, kind);

  if (!canTransition(INGEST_TRANSITIONS, job.status, "running")) {
    throw new Error(`ingest.${kind}: illegal transition ${job.status} -> running`);
  }
  const { error: runningError } = await supabase
    .from("ingest_job")
    .update({
      status: "running",
      attempts: job.attempts + 1,
      heartbeat_at: new Date().toISOString(),
      error_code: null,
    })
    .eq("id", job.id);
  if (runningError) throw runningError;
  await recordStateEvent({ subjectKind: "ingest_job", subjectId: job.id, from: job.status, to: "running" });

  let result: IngestWorkerResult;
  try {
    result = await worker();
  } catch (err) {
    result = { ok: false, errorCode: err instanceof Error ? err.message : "unknown_error" };
  }

  if (result.ok) {
    const { error } = await supabase
      .from("ingest_job")
      .update({ status: "done", detail: result.detail, heartbeat_at: null })
      .eq("id", job.id);
    if (error) throw error;
    await recordStateEvent({ subjectKind: "ingest_job", subjectId: job.id, from: "running", to: "done" });
    return { id: job.id, status: "done", detail: result.detail };
  }

  const { error } = await supabase
    .from("ingest_job")
    .update({ status: "failed", error_code: result.errorCode, heartbeat_at: null })
    .eq("id", job.id);
  if (error) throw error;
  await recordStateEvent({
    subjectKind: "ingest_job",
    subjectId: job.id,
    from: "running",
    to: "failed",
    errorCode: result.errorCode,
  });
  return { id: job.id, status: "failed", error_code: result.errorCode };
}

/**
 * R2″ 고아 회수 (액션플랜 라인 983-984): running + heartbeat 만료 → failed로
 * 강제 회수. 상주 워커 금지 원칙에 따라 다음 요청 진입 시 lazy 실행.
 */
export async function reclaimStaleIngestJobs(): Promise<number> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ingest_job")
    .select("id,attempts,heartbeat_at")
    .eq("status", "running");
  if (error) throw error;

  const now = Date.now();
  let reclaimed = 0;
  for (const row of data ?? []) {
    const heartbeatAgeSeconds = row.heartbeat_at
      ? (now - new Date(row.heartbeat_at).getTime()) / 1000
      : null;
    const outcome = recoverIngestJob({ status: "running", heartbeatAgeSeconds, attempts: row.attempts });
    if (!outcome) continue;

    const { error: updateError } = await supabase
      .from("ingest_job")
      .update({ status: outcome.to, error_code: "heartbeat_timeout", heartbeat_at: null })
      .eq("id", row.id);
    if (updateError) throw updateError;
    await recordStateEvent({
      subjectKind: "ingest_job",
      subjectId: row.id,
      from: "running",
      to: outcome.to,
      rule: outcome.rule,
      errorCode: "heartbeat_timeout",
    });
    reclaimed++;
  }
  return reclaimed;
}
