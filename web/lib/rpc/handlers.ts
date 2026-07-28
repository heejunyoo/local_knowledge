// P4a 읽기 메서드 핸들러. 각 함수는 JSON-RPC의 `result` 페이로드만 반환한다
// (봉투는 lib/rpc/dispatch.ts + app/api/rpc/route.ts가 씌운다).
//
// 스코프: core.*, assistant.*, timeline.list, diet.{day_summary,week_review,
// goals,profile.get,ping}. diet.dashboard·diet.fasting.status는 별도 세션
// (REFACTOR_STATUS.md 참고). knowledge/corpus/inbox는 P4a-6.
import { createClient } from "@/lib/supabase/server";
import * as dietRead from "@/lib/domain/diet-read";
import { fetchDietGoals, fetchDietProfile, fetchRecentDietSnapshots } from "@/lib/db/diet";
import { fetchInboxOpenCount, fetchInboxList, insertInboxItem } from "@/lib/db/inbox";
import { fetchCorpusStatus } from "@/lib/db/corpus";
import { searchDocs } from "@/lib/db/search";

export async function core_ping() {
  return { pong: true };
}

export async function core_services() {
  return { knowledge: true, diet: true, assistant: true };
}

/**
 * 원본 골든(knowledge.health, core.health의 내장 "knowledge" 키 — 같은
 * RPCMethod.health 핸들러)의 db_path/vault_path/asr_engine/llama_ready/
 * llm_engine/whisper_ready/recording_count/review_needed_count는 전부 Mac
 * 로컬 데몬 상태다. 액션플랜 §8이 core.health에 대해 이 필드들의 제거를
 * 명시하고, G4a-1 diff-0는 두 메서드 모두 문서화된 예외로 처리하기로 오너가
 * 결정했다(REFACTOR_STATUS.md). DB 도달성만 반영한다.
 */
export async function knowledge_health() {
  const supabase = await createClient();
  const { error } = await supabase.from("settings").select("key").limit(1);
  return { ok: !error };
}

export async function core_health() {
  const [today] = await fetchRecentDietSnapshots(0);
  return {
    ok: true,
    services: { knowledge: true, diet: true, assistant: true, inbox: true, health: true },
    knowledge: await knowledge_health(),
    // 골든의 core.health.diet.totals는 전부 false다(0.0 → NSNumber(bool:false)로
    // 잘못 브리징된 Swift 원본의 버그로 보임 — diet.day_summary 골든은 같은
    // daySummaryDict()를 정상적으로 0으로 캡처했다). 버그를 재현하지 않고 정확한
    // 값을 반환한다 — tests/regression/golden.test.ts가 이 필드는 diff-0 대상에서 뺐다.
    diet: dietRead.daySummaryDict(today),
  };
}

/** F-1: 미팅 리뷰 파이프라인 전면 폐기로 review_pending은 항상 0. */
const REVIEW_PENDING = 0;

export async function assistant_today() {
  const now = new Date();
  const snapshots = await fetchRecentDietSnapshots(29, now); // today-first, up to 30일(연속기록용)
  const [today, yesterday] = snapshots;
  const goals = await fetchDietGoals();
  const gaps = dietRead.missingLogChecklist(now, today, yesterday);
  const sleepHint = dietRead.sleepCoachHint(dietRead.latestSleepHours(snapshots.slice(0, 3)));
  const streak = dietRead.activityStreak(snapshots);
  const inboxOpen = await fetchInboxOpenCount();
  const suggest = dietRead.suggestedAction(now, today);
  const timeline = dietRead.timelineEvents(today);

  const nextActions: Record<string, unknown>[] = [];
  const firstGap = gaps[0];
  if (firstGap) {
    const action: Record<string, unknown> = { kind: "gap", label: firstGap.label };
    if (firstGap.slot) action.slot = firstGap.slot;
    nextActions.push(action);
  }
  const suggestAction: Record<string, unknown> = {
    kind: "diet_suggest",
    label: suggest.title,
    subtitle: suggest.subtitle,
  };
  if (suggest.slot) suggestAction.slot = suggest.slot;
  nextActions.push(suggestAction);
  if (inboxOpen > 0) nextActions.push({ kind: "inbox", label: `인박스 ${inboxOpen}건 정리` });

  const body: Record<string, unknown> = {
    line: today.summaryText,
    kcal: today.kcal,
    protein_g: today.proteinG,
    workout_minutes: today.workoutMinutes,
    meal_count: today.meals.length,
    target_kcal: goals.targetKcal,
    target_protein_g: goals.targetProteinG,
    suggest: { title: suggest.title, subtitle: suggest.subtitle },
    streak_days: streak,
  };
  if (sleepHint) body.sleep_hint = sleepHint;

  return {
    date: today.date,
    body,
    knowledge: {
      review_pending: REVIEW_PENDING,
      line: REVIEW_PENDING > 0 ? `저장 전 요약 ${REVIEW_PENDING}건` : "확인할 요약 없음",
      inbox_open: inboxOpen,
    },
    gaps,
    timeline,
    next_actions: nextActions,
    version: 2,
  };
}

export async function assistant_week_review() {
  const now = new Date();
  const snapshots = await fetchRecentDietSnapshots(29, now);
  const bars = snapshots.slice(0, 7).slice().reverse().map(dietRead.dayBarFrom);
  const goals = await fetchDietGoals();
  const streak = dietRead.activityStreak(snapshots);
  const sleepHint = dietRead.sleepCoachHint(dietRead.latestSleepHours(snapshots.slice(0, 3)));
  const inboxOpen = await fetchInboxOpenCount();
  return dietRead.buildAssistantWeekReview(bars, goals, streak, sleepHint, inboxOpen);
}

export async function assistant_gaps() {
  const now = new Date();
  const snapshots = await fetchRecentDietSnapshots(2, now);
  const gaps = dietRead.missingLogChecklist(now, snapshots[0], snapshots[1]);
  const sleepHint = dietRead.sleepCoachHint(dietRead.latestSleepHours(snapshots));
  return { gaps, sleep_hint: sleepHint };
}

export async function timeline_list() {
  const [today] = await fetchRecentDietSnapshots(0);
  const events = dietRead.timelineEvents(today);
  return { events, count: events.length };
}

export async function diet_day_summary() {
  const [today] = await fetchRecentDietSnapshots(0);
  return dietRead.daySummaryDict(today);
}

export async function diet_week_review() {
  const snapshots = await fetchRecentDietSnapshots(6);
  const bars = snapshots.slice().reverse().map(dietRead.dayBarFrom);
  const goals = await fetchDietGoals();
  return dietRead.weekReview(bars, goals);
}

export async function diet_goals() {
  return dietRead.goalsDict(await fetchDietGoals());
}

export async function diet_profile_get() {
  const profile = await fetchDietProfile();
  if (!profile) return { exists: false };
  return dietRead.profileDict(profile);
}

export async function diet_ping() {
  return { ok: true, enabled: true, engine: "diet-inproc/v1" };
}

export async function corpus_status() {
  return fetchCorpusStatus();
}

/**
 * Swift 원본(handleSearch)의 `{q, hits:[{doc_id,source_type,title,snippet}]}`
 * 형태를 유지한다. search_docs() RPC(doc_id,rank만 반환)에 search_doc 테이블을
 * 조인해 title/snippet을 채운다. 골든 회귀(G4a-1) 대상이 아니다 — 검색은
 * G4a-6(compare-search.ts, 30개 쿼리 recall 비교)이 별도로 검증한다.
 */
export async function knowledge_search(params: unknown) {
  const p = (params ?? {}) as { q?: string; query?: string; limit?: number };
  const q = (p.q ?? p.query ?? "").trim();
  if (!q) return { hits: [], q };

  const limit = Math.max(1, Math.min(50, Math.trunc(p.limit ?? 20)));
  const hits = await searchDocs(q, { limit });
  if (hits.length === 0) return { hits: [], q };

  const supabase = await createClient();
  const { data: docs, error } = await supabase
    .from("search_doc")
    .select("doc_id,source_type,title,body")
    .in(
      "doc_id",
      hits.map((h) => h.docId),
    );
  if (error) throw error;
  const byId = new Map((docs ?? []).map((d) => [d.doc_id, d]));

  return {
    q,
    hits: hits.map((h) => {
      const doc = byId.get(h.docId);
      return {
        doc_id: h.docId,
        source_type: doc?.source_type ?? null,
        title: doc?.title ?? null,
        snippet: doc?.body ? doc.body.slice(0, 160) : null,
      };
    }),
  };
}

export async function inbox_list(params: unknown) {
  const p = (params ?? {}) as { include_promoted?: boolean };
  const items = await fetchInboxList(Boolean(p.include_promoted));
  return { items, open_count: await fetchInboxOpenCount() };
}

export async function inbox_create(params: unknown) {
  const p = (params ?? {}) as { text?: string; message?: string };
  return insertInboxItem(p.text ?? p.message ?? "");
}
