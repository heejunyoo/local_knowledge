import { createClient } from "@/lib/supabase/server";

// 원본 pipeline_events의 축소 계승 — 서버리스에서 "왜 여기서 멈췄나"를
// 사후에 알 수 있는 유일한 수단(액션플랜 라인 986).
export interface StateEventInput {
  subjectKind: "inbox_item" | "ingest_job";
  subjectId: string;
  from: string | null;
  to: string;
  rule?: string;
  errorCode?: string;
}

export async function recordStateEvent(input: StateEventInput): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("state_event").insert({
    subject_kind: input.subjectKind,
    subject_id: input.subjectId,
    from_status: input.from,
    to_status: input.to,
    rule: input.rule ?? null,
    error_code: input.errorCode ?? null,
  });
  if (error) throw error;
}
