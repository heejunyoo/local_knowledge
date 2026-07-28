import { createClient } from "@/lib/supabase/server";

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
