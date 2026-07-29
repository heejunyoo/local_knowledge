import { createClient } from "@/lib/supabase/server";
import { CachedAnswer, LlmAnswerCacheStore, MAX_ENTRIES, TTL_SECONDS } from "./cache";

interface CacheRow {
  cache_key: string;
  answer: { text: string; engine: string };
  created_at: string;
}

/** `llm_answer_cache` 테이블(001_init.sql에서 이미 생성됨) 기반 구현. */
export class DbLlmAnswerCacheStore implements LlmAnswerCacheStore {
  async get(key: string): Promise<CachedAnswer | null> {
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("llm_answer_cache")
      .select("cache_key,answer,created_at")
      .eq("cache_key", key)
      .maybeSingle();
    if (error) throw error;
    const row = data as CacheRow | null;
    if (!row) return null;
    const ageSeconds = (Date.now() - new Date(row.created_at).getTime()) / 1000;
    if (ageSeconds > TTL_SECONDS) return null;
    if (!row.answer?.text) return null;
    return { text: row.answer.text, engine: `${row.answer.engine}+cache` };
  }

  async put(key: string, question: string, answer: CachedAnswer, provider: string): Promise<void> {
    if (!answer.text) return;
    const supabase = await createClient();
    const { error } = await supabase.from("llm_answer_cache").upsert({
      cache_key: key,
      question,
      answer: { text: answer.text, engine: answer.engine },
      provider,
      created_at: new Date().toISOString(),
    });
    if (error) throw error;
    await this.pruneIfNeeded(supabase);
  }

  private async pruneIfNeeded(supabase: Awaited<ReturnType<typeof createClient>>): Promise<void> {
    const { data, error } = await supabase
      .from("llm_answer_cache")
      .select("cache_key")
      .order("created_at", { ascending: false })
      .range(MAX_ENTRIES, MAX_ENTRIES + 500);
    if (error) throw error;
    const staleKeys = (data ?? []).map((r) => (r as { cache_key: string }).cache_key);
    if (staleKeys.length === 0) return;
    const { error: delErr } = await supabase.from("llm_answer_cache").delete().in("cache_key", staleKeys);
    if (delErr) throw delErr;
  }
}
