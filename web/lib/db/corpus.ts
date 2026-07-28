import { createClient } from "@/lib/supabase/server";

// Swift 원본: Packages/KnowledgeRPC/Sources/KnowledgeRPC/PipelineService.swift
// corpusStatusJSON(). listConnectedSources()가 `ORDER BY source_type, label`을
// 쓰므로 골든과 동일한 정렬을 위해 그대로 재현한다(normalize.py는 객체 키만
// 정렬하고 배열 순서는 그대로 diff하므로 순서가 어긋나면 G4a-1이 깨진다).
export async function fetchCorpusStatus() {
  const supabase = await createClient();
  const [sourcesRes, meetingRes, notesRes, obsidianRes, fileRes, totalRes] = await Promise.all([
    supabase
      .from("connected_source")
      .select("id,source_type,label,root_path,enabled,last_sync_at,last_error,unit_count")
      .order("source_type", { ascending: true })
      .order("label", { ascending: true }),
    supabase.from("knowledge_unit").select("unit_id", { count: "exact", head: true }).eq("source_type", "meeting"),
    supabase.from("knowledge_unit").select("unit_id", { count: "exact", head: true }).eq("source_type", "notes"),
    supabase.from("knowledge_unit").select("unit_id", { count: "exact", head: true }).eq("source_type", "obsidian"),
    supabase.from("knowledge_unit").select("unit_id", { count: "exact", head: true }).eq("source_type", "file"),
    supabase.from("knowledge_unit").select("unit_id", { count: "exact", head: true }),
  ]);
  for (const res of [sourcesRes, meetingRes, notesRes, obsidianRes, fileRes, totalRes]) {
    if (res.error) throw res.error;
  }

  return {
    total_units: totalRes.count ?? 0,
    meetings: meetingRes.count ?? 0,
    notes: notesRes.count ?? 0,
    obsidian: obsidianRes.count ?? 0,
    files: fileRes.count ?? 0,
    sources: (sourcesRes.data ?? []).map((s) => ({
      id: s.id,
      source_type: s.source_type,
      label: s.label,
      root_path: s.root_path,
      enabled: s.enabled,
      last_sync_at: s.last_sync_at,
      last_error: s.last_error,
      unit_count: s.unit_count,
    })),
  };
}

/**
 * corpus.sync 워커 (ingest_job kind='corpus_sync'). 원본 Swift는 로컬 파일을
 * 직접 스캔했지만(GitHub PAT 미발급 상태에서 웹은 재현 불가), 이미 DB에 있는
 * knowledge_unit 집계로 connected_source.unit_count/last_sync_at을 재계산하는
 * 실작업으로 대체한다(오너 승인, REFACTOR_STATUS 참고). 외부 API 불필요 —
 * G4a-4(고아 회수→재큐잉) 검증에 이 워커를 쓴다. GitHub 기반 실제 vault
 * 재수집은 PAT 발급 후 별도 task(REFACTOR_BACKLOG.md).
 */
export async function syncConnectedSourceStats(): Promise<{ updated: number }> {
  const supabase = await createClient();
  const { data: sources, error: sourcesError } = await supabase
    .from("connected_source")
    .select("id,source_type");
  if (sourcesError) throw sourcesError;

  let updated = 0;
  for (const source of sources ?? []) {
    const { count, error } = await supabase
      .from("knowledge_unit")
      .select("unit_id", { count: "exact", head: true })
      .eq("source_type", source.source_type);
    if (error) throw error;

    const { error: updateError } = await supabase
      .from("connected_source")
      .update({ unit_count: count ?? 0, last_sync_at: new Date().toISOString(), last_error: null })
      .eq("id", source.id);
    if (updateError) throw updateError;
    updated++;
  }
  return { updated };
}
