import { createClient } from "@/lib/supabase/server";
import {
  canTransition,
  recoverInboxItem,
  DEFAULT_MAX_ATTEMPTS,
  DEFAULT_HEARTBEAT_GRACE_SECONDS,
  INBOX_TRANSITIONS,
  type InboxStatus,
} from "@/lib/domain/state-machine";
import { recordStateEvent } from "@/lib/db/state-event";

export async function fetchInboxOpenCount(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("inbox_item")
    .select("id", { count: "exact", head: true })
    .eq("status", "open");
  if (error) throw error;
  return count ?? 0;
}

export interface InboxItemDict {
  id: string;
  ts: string;
  text: string;
  status: string;
  promoted_path?: string;
}

function toDict(row: {
  id: string;
  ts: string;
  text: string;
  status: string;
  promoted_path: string | null;
}): InboxItemDict {
  const d: InboxItemDict = { id: row.id, ts: row.ts, text: row.text, status: row.status };
  if (row.promoted_path != null) d.promoted_path = row.promoted_path;
  return d;
}

// Swift 원본(InboxStore.list)은 status가 open|promoted 2종뿐이었지만, 이관된
// 상태기계(D-3)는 promoting|promote_failed도 갖는다. include_promoted=false는
// 원본과 동일하게 status='open'만 남긴다 — promoting/promote_failed는 진행
// 중/실패 상태라 "열려 있는" 목록에 포함하지 않는다.
export async function fetchInboxList(includePromoted: boolean): Promise<InboxItemDict[]> {
  const supabase = await createClient();
  let query = supabase.from("inbox_item").select("id,ts,text,status,promoted_path").order("ts", { ascending: false });
  if (!includePromoted) query = query.eq("status", "open");
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []).map(toDict);
}

export async function insertInboxItem(text: string): Promise<InboxItemDict> {
  const trimmed = text.trim();
  if (!trimmed) throw new Error("inbox.create: empty text");

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const ownerId = claims?.claims.sub;
  if (!ownerId) throw new Error("inbox.create: no authenticated user");

  const { data, error } = await supabase
    .from("inbox_item")
    .insert({ owner_id: ownerId, text: trimmed })
    .select("id,ts,text,status,promoted_path")
    .single();
  if (error) throw error;
  return toDict(data);
}

// ---------------------------------------------------------------------------
// D-3 상태기계: inbox_item 승격 파이프라인
// ---------------------------------------------------------------------------

const VAULT_INBOX_DIR = "10 📥 수집함";
const VAULT_REPO = "heejunyoo/knowledge-vault";

function vaultInboxPath(id: string): string {
  return `${VAULT_INBOX_DIR}/${id}.md`;
}

export type VaultCommitResult = { ok: true; path: string } | { ok: false; errorCode: string };
export type VaultCommitFn = (item: { id: string; text: string }) => Promise<VaultCommitResult>;

/**
 * GitHub Contents API로 vault 레포에 md를 커밋한다(서버리스에 git 바이너리
 * 없음 — 액션플랜 라인 972). 커밋 메시지 `web: ...` 규약(P2-3), 쓰기 경로는
 * `10 📥 수집함/` 한정. VAULT_GITHUB_TOKEN 미발급 상태에서는 실패로 처리한다
 * (G4a-2는 토큰 발급 후 별도 세션에서 검증 — REFACTOR_STATUS.md).
 */
export const defaultVaultCommit: VaultCommitFn = async (item) => {
  const token = process.env.VAULT_GITHUB_TOKEN;
  if (!token) return { ok: false, errorCode: "vault_token_missing" };

  const path = vaultInboxPath(item.id);
  const res = await fetch(
    `https://api.github.com/repos/${VAULT_REPO}/contents/${encodeURIComponent(path)}`,
    {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
      },
      body: JSON.stringify({
        message: `web: ${path}`,
        content: Buffer.from(item.text, "utf-8").toString("base64"),
      }),
    },
  );
  if (!res.ok) return { ok: false, errorCode: `github_${res.status}` };
  return { ok: true, path };
};

async function fetchInboxRow(supabase: Awaited<ReturnType<typeof createClient>>, id: string) {
  const { data, error } = await supabase
    .from("inbox_item")
    .select("id,text,status,attempts")
    .eq("id", id)
    .single();
  if (error) throw error;
  return data as { id: string; text: string; status: InboxStatus; attempts: number };
}

async function transitionInboxItem(
  supabase: Awaited<ReturnType<typeof createClient>>,
  id: string,
  from: InboxStatus,
  to: InboxStatus,
  patch: Record<string, unknown>,
  rule?: string,
  errorCode?: string,
): Promise<void> {
  if (!canTransition(INBOX_TRANSITIONS, from, to)) {
    throw new Error(`inbox: illegal transition ${from} -> ${to}`);
  }
  const { error } = await supabase.from("inbox_item").update(patch).eq("id", id);
  if (error) throw error;
  await recordStateEvent({ subjectKind: "inbox_item", subjectId: id, from, to, rule, errorCode });
}

/**
 * open|promote_failed 상태의 항목을 promoted로 승격 시도한다. 커밋 함수는
 * 주입형(기본값 defaultVaultCommit) — GitHub PAT 없이도 가짜 커밋 함수로
 * 상태기계 로직 자체를 테스트할 수 있다.
 */
export async function promoteInboxItem(
  id: string,
  commit: VaultCommitFn = defaultVaultCommit,
): Promise<InboxItemDict> {
  const supabase = await createClient();
  const row = await fetchInboxRow(supabase, id);

  if (row.status === "promote_failed" && row.attempts >= DEFAULT_MAX_ATTEMPTS) {
    throw new Error("inbox.promote: max attempts reached");
  }
  if (!canTransition(INBOX_TRANSITIONS, row.status, "promoting")) {
    throw new Error(`inbox.promote: illegal transition from ${row.status}`);
  }

  await transitionInboxItem(supabase, id, row.status, "promoting", {
    status: "promoting",
    attempts: row.attempts + 1,
    heartbeat_at: new Date().toISOString(),
    error_code: null,
  });

  const result = await commit({ id: row.id, text: row.text });

  if (result.ok) {
    await transitionInboxItem(supabase, id, "promoting", "promoted", {
      status: "promoted",
      promoted_path: result.path,
      heartbeat_at: null,
    });
  } else {
    await transitionInboxItem(
      supabase,
      id,
      "promoting",
      "promote_failed",
      { status: "promote_failed", error_code: result.errorCode, heartbeat_at: null },
      undefined,
      result.errorCode,
    );
  }

  const updated = await supabase
    .from("inbox_item")
    .select("id,ts,text,status,promoted_path")
    .eq("id", id)
    .single();
  if (updated.error) throw updated.error;
  return toDict(updated.data);
}

export type VaultPathChecker = (path: string) => Promise<boolean>;

export const defaultVaultPathChecker: VaultPathChecker = async (path) => {
  const token = process.env.VAULT_GITHUB_TOKEN;
  if (!token) return false;
  const res = await fetch(
    `https://api.github.com/repos/${VAULT_REPO}/contents/${encodeURIComponent(path)}`,
    { headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" } },
  );
  return res.ok;
};

/**
 * R2′/R3′ 고아 회수 (액션플랜 라인 973-974): status='promoting'이고
 * heartbeat_at이 만료된 항목을 promoted(커밋은 됐는데 응답 전에 죽음) 또는
 * promote_failed로 회수한다. 상주 워커 없이 다음 요청 진입 시 lazy 실행.
 */
export async function reclaimStaleInboxItems(
  checkPath: VaultPathChecker = defaultVaultPathChecker,
): Promise<number> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inbox_item")
    .select("id,attempts,heartbeat_at")
    .eq("status", "promoting");
  if (error) throw error;

  const now = Date.now();
  let reclaimed = 0;
  for (const row of data ?? []) {
    const heartbeatAgeSeconds = row.heartbeat_at
      ? (now - new Date(row.heartbeat_at).getTime()) / 1000
      : null;
    if (heartbeatAgeSeconds == null || heartbeatAgeSeconds < DEFAULT_HEARTBEAT_GRACE_SECONDS) continue;

    const vaultPathExists =
      row.attempts >= DEFAULT_MAX_ATTEMPTS ? false : await checkPath(vaultInboxPath(row.id));
    const outcome = recoverInboxItem({
      status: "promoting",
      heartbeatAgeSeconds,
      attempts: row.attempts,
      vaultPathExists,
    });
    if (!outcome) continue;

    await transitionInboxItem(
      supabase,
      row.id,
      "promoting",
      outcome.to,
      {
        status: outcome.to,
        heartbeat_at: null,
        ...(outcome.to === "promoted"
          ? { promoted_path: vaultInboxPath(row.id) }
          : { error_code: "heartbeat_timeout" }),
      },
      outcome.rule,
      outcome.to === "promote_failed" ? "heartbeat_timeout" : undefined,
    );
    reclaimed++;
  }
  return reclaimed;
}
