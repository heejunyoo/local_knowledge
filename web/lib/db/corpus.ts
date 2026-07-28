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
