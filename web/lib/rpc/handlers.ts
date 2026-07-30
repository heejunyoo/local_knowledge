// P4a 읽기 메서드 핸들러. 각 함수는 JSON-RPC의 `result` 페이로드만 반환한다
// (봉투는 lib/rpc/dispatch.ts + app/api/rpc/route.ts가 씌운다).
//
// 스코프: core.*, assistant.*, timeline.list, diet.{day_summary,week_review,
// goals,profile.get,ping}. diet.dashboard·diet.fasting.status는 별도 세션
// (REFACTOR_STATUS.md 참고). knowledge/corpus/inbox는 P4a-6, D-3 상태기계
// 쓰기(inbox.promote/corpus.sync/search.reindex)는 P4a-9(task 9).
import { createClient } from "@/lib/supabase/server";
import * as dietRead from "@/lib/domain/diet-read";
import * as nutritionCalc from "@/lib/domain/diet-nutrition-calc";
import { enrichWithLlm } from "@/lib/diet/nutrition-enrich";
import * as dietDb from "@/lib/db/diet";
import { fetchDietGoals, fetchDietProfile, fetchRecentDietSnapshots } from "@/lib/db/diet";
import {
  fetchInboxOpenCount,
  fetchInboxList,
  insertInboxItem,
  promoteInboxItem,
  reclaimStaleInboxItems,
} from "@/lib/db/inbox";
import { fetchCorpusStatus } from "@/lib/db/corpus";
import { searchDocs } from "@/lib/db/search";
import { runIngestJob, reclaimStaleIngestJobs } from "@/lib/db/ingest";
import * as rag from "@/lib/rag/ask";
import * as chatDomain from "@/lib/domain/chat";

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

/**
 * 원본(MobileHTTPServer.swift `case "diet.estimate_nutrition"`)과 동일한
 * 파라미터 우선순위: text가 있고 amount<=0이면 자유 텍스트 파싱, 아니면
 * food/amount/unit으로 직접 추정.
 *
 * C3(웹 신규): 규칙 기반 카탈로그가 못 맞춘 음식만 LLM으로 보강한다
 * (`enrichWithLlm`). 카탈로그 매칭 시 LLM 호출은 0회이고, LLM이 없거나
 * 실패하면 기존 일반식 평균 추정치가 그대로 나간다 — 에러 경로가 아니다.
 */
export async function diet_estimate_nutrition(params: unknown) {
  const p = (params ?? {}) as {
    food?: string; q?: string; text?: string; amount?: number; unit?: string;
  };
  const food = p.food ?? p.q ?? p.text ?? "";
  const amount = Number(p.amount ?? 0) || 0;
  const unit: nutritionCalc.NutritionUnit = (p.unit ?? "g").toLowerCase() === "ml" ? "ml" : "g";

  const e = p.text !== undefined && amount <= 0
    ? nutritionCalc.parse(p.text)
    : nutritionCalc.estimate(food, amount, unit);
  if (!e) return { matched: false };

  const enriched = await enrichWithLlm(e);
  return nutritionCalc.estimateAsDict(enriched.estimate, enriched.source);
}

export async function corpus_status() {
  // 상주 워커 금지 원칙(방향성 §4.1-1) — 다음 요청 진입 시 고아 ingest_job을
  // lazy하게 회수한다(R2″, G4a-4).
  await reclaimStaleIngestJobs();
  return fetchCorpusStatus();
}

export async function corpus_sync() {
  return runIngestJob("corpus_sync");
}

export async function search_reindex() {
  return runIngestJob("search_reindex");
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

interface KnowledgeAskResult {
  question: string;
  answer: string;
  engine: string;
  citations: {
    unit_id: string;
    title: string;
    source_type: string;
    snippet: string;
    score: number;
  }[];
}

/** 원본 MobileHTTPServer `case "knowledge.ask"|"knowledge.ask.fast"` 응답 계약과 동일한 필드명. */
function toKnowledgeAskResult(r: Awaited<ReturnType<typeof rag.ask>>): KnowledgeAskResult {
  return {
    question: r.question,
    answer: r.answer,
    engine: r.engine,
    citations: r.citations.slice(0, 8).map((c) => ({
      unit_id: c.unitId,
      title: c.title,
      source_type: c.sourceType,
      snippet: c.snippet,
      score: c.score,
    })),
  };
}

/** 원본: knowledge.ask — 검색(P1 확정 방식) → LLM(캐스케이드) → 실패 시 extractive(1급 경로, G6-3). */
export async function knowledge_ask(params: unknown) {
  const p = (params ?? {}) as { q?: string; question?: string; limit?: number; use_llama?: boolean };
  const q = p.q ?? p.question ?? "";
  const limit = Math.max(1, Math.min(20, Math.trunc(p.limit ?? 8)));
  const useLlm = p.use_llama ?? true;
  return toKnowledgeAskResult(await rag.ask(q, { topK: limit, useLlm }));
}

/** 원본: knowledge.ask.fast — 검색+extractive만(LLM 스킵, UI 즉시 응답용). */
export async function knowledge_ask_fast(params: unknown) {
  const p = (params ?? {}) as { q?: string; question?: string; limit?: number };
  const q = p.q ?? p.question ?? "";
  const limit = Math.max(1, Math.min(20, Math.trunc(p.limit ?? 8)));
  return toKnowledgeAskResult(await rag.askFast(q, { topK: limit }));
}

interface ChatSource {
  service: string;
  title: string;
  snippet: string;
  unit_id?: string;
}

/** 원본 handleChat의 knowledge 분기: askFast → refine 시도, 실패 시 fast 그대로. */
async function handleKnowledgeChat(message: string) {
  const fast = await rag.askFast(message, { topK: 8 });
  const answer = (await rag.refine(message, fast.citations)) ?? fast;
  const sources: ChatSource[] = answer.citations.slice(0, 6).map((c) => ({
    service: "knowledge",
    title: c.title,
    snippet: c.snippet,
    unit_id: c.unitId,
  }));
  return {
    answer: answer.answer,
    engine: answer.engine,
    sources,
    trace: ["intent:knowledge", "knowledge.ask"],
    intent: "knowledge",
  };
}

/** 원본 handleMixedChat — diet 컨텍스트를 먼저 모으고 knowledge 검색을 이어붙인다(W2). */
async function handleMixedChat(message: string) {
  const trace = ["intent:mixed"];
  const coach = (await diet_coach({ message })) as { answer: string; engine: string };
  trace.push("diet.coach");
  const dayLine = ((await diet_day_summary()) as { summary_text?: string }).summary_text ?? "";
  const ctx = await fetchDietGatewayContext();
  const sleepHint = dietRead.sleepCoachHint(dietRead.latestSleepHours(ctx.sevenDay.slice(0, 3))) ?? "";
  const weekLine = ((await diet_week_review()) as { summary_text?: string }).summary_text ?? "";

  const fast = await rag.askFast(message, { topK: 6 });
  const knowledge = (await rag.refine(message, fast.citations)) ?? fast;
  trace.push("knowledge.ask");

  const parts: string[] = ["【몸】"];
  if (coach.answer) parts.push(coach.answer);
  if (dayLine) parts.push(dayLine);
  if (weekLine) parts.push(weekLine);
  if (sleepHint) parts.push(sleepHint);
  parts.push("");
  parts.push("【지식】");
  parts.push(knowledge.answer);

  const sources: ChatSource[] = [{ service: "diet", title: "오늘·주간", snippet: dayLine }];
  for (const c of knowledge.citations.slice(0, 4)) {
    sources.push({ service: "knowledge", title: c.title, snippet: c.snippet, unit_id: c.unitId });
  }

  return {
    answer: parts.join("\n"),
    engine: `mixed/${knowledge.engine}`,
    sources,
    trace,
    intent: "mixed",
  };
}

/** 원본 handleDietChat — 운동/식사 휴리스틱 기록 후 diet.coach로 폴백. */
async function handleDietChat(message: string) {
  const trace = ["intent:diet"];

  if (message.includes("운동") || message.toLowerCase().includes("workout")) {
    const minutes = chatDomain.firstInt(message) ?? 20;
    let kind = message.replace(/운동/g, "").replace(/workout/gi, "");
    kind = kind.replace(/\d+\s*분/g, "").trim();
    const w = await dietDb.insertWorkout({
      kind: kind ? kind.slice(0, 40) : "workout",
      minutes,
      intensity: null,
    });
    trace.push("diet.log_workout");
    const day = ((await diet_day_summary()) as { summary_text?: string }).summary_text ?? "";
    return {
      answer: `운동 기록했어요: ${w.kind} ${w.minutes}분.\n${day}`,
      engine: "diet-rules/v1",
      sources: [{ service: "diet", title: "workout", snippet: `${w.kind} ${w.minutes}m` }] as ChatSource[],
      trace,
    };
  }

  if (
    message.includes("kcal") ||
    message.includes("칼로리") ||
    message.includes("먹") ||
    message.includes("식사") ||
    message.includes("점심") ||
    message.includes("저녁") ||
    message.includes("아침")
  ) {
    const kcal = chatDomain.firstDouble(message);
    const meal = await dietDb.insertMeal({ items: [message], kcal, proteinG: null, note: message });
    trace.push("diet.log_meal");
    const day = ((await diet_day_summary()) as { summary_text?: string }).summary_text ?? "";
    return {
      answer: `식사 기록했어요${kcal != null ? ` (${Math.trunc(kcal)} kcal)` : ""}.\n${day}`,
      engine: "diet-rules/v1",
      sources: [{ service: "diet", title: "meal", snippet: meal.items.join(", ") }] as ChatSource[],
      trace,
    };
  }

  const coach = (await diet_coach({ message })) as { answer: string; engine: string };
  trace.push("diet.coach");
  const dayLine = ((await diet_day_summary()) as { summary_text?: string }).summary_text ?? "";
  return {
    answer: coach.answer,
    engine: coach.engine,
    sources: [{ service: "diet", title: "오늘", snippet: dayLine }] as ChatSource[],
    trace,
  };
}

/** 원본 MobileHTTPServer.handleChat — REST 전용(POST /v1/chat 대응, POST /api/chat). */
export async function chat_send(params: unknown) {
  const p = (params ?? {}) as { message?: string; mode?: string };
  const message = p.message ?? "";
  const mode = (p.mode ?? "auto").toLowerCase();
  const intent = chatDomain.classifyIntent(message, mode);

  if (intent === "diet") return handleDietChat(message);
  if (intent === "mixed") return handleMixedChat(message);
  return handleKnowledgeChat(message);
}

export async function inbox_list(params: unknown) {
  // 상주 워커 금지 원칙(방향성 §4.1-1) — 다음 요청 진입 시 고아 inbox_item을
  // lazy하게 회수한다(R2′/R3′, G4a-3).
  await reclaimStaleInboxItems();
  const p = (params ?? {}) as { include_promoted?: boolean };
  const items = await fetchInboxList(Boolean(p.include_promoted));
  return { items, open_count: await fetchInboxOpenCount() };
}

export async function inbox_create(params: unknown) {
  const p = (params ?? {}) as { text?: string; message?: string };
  return insertInboxItem(p.text ?? p.message ?? "");
}

export async function inbox_promote(params: unknown) {
  const p = (params ?? {}) as { id?: string };
  if (!p.id) throw new Error("inbox.promote: missing id");
  return promoteInboxItem(p.id);
}

/**
 * 원본(`MobileHTTPServer.swift`의 `health.sync_status`)은 상태와 무관한
 * 고정값을 반환한다 — Sensor SoT는 기기의 Apple Health이고 Core는 ingest로
 * 미러링만 한다는 사실 자체가 응답이다. `health.ingest`(원본에서 이 핸들러와
 * 같은 switch에 있던 짝)는 diet.log_workout/diet.log_metric에 의존하는
 * 도메인 로직 본체라 P4b로 이관됐다(액션플랜 §8, 2026-07-28 정정) — 이 함수는
 * 그 이관과 무관하게 그대로 P4a에 남는다.
 */
export async function health_sync_status() {
  return { ok: true, mirror: "diet", pull_mode: "app_open", mac_healthkit: false };
}

// ---------------------------------------------------------------------------
// P4b: diet 쓰기 도메인 + dashboard/fasting/plan/coach 조립.
// Swift 원본: MobileHTTPServer.swift의 diet.* case들, DietStore.swift.
// ---------------------------------------------------------------------------

interface DietGatewayContext {
  now: Date;
  /** 오늘이 먼저 오는 30일 스냅샷(activityStreak 스캔 범위, assistant_today와 동일). */
  snapshots30: dietRead.DaySnapshot[];
  /** snapshots30 앞 7개 — 주간 바/평균 섭취 계산용. */
  sevenDay: dietRead.DaySnapshot[];
  today: dietRead.DaySnapshot;
  profile: dietRead.Profile | null;
  goals: dietRead.Goals;
  metricsAsc: dietRead.Metric[];
  workoutsAsc: dietRead.Workout[];
  lastMeal: dietRead.Meal | null;
  fastingPrefs: dietRead.FastingPrefs;
  avgDailyIntakeKcal: number | null;
}

async function fetchDietGatewayContext(now: Date = new Date()): Promise<DietGatewayContext> {
  const [snapshots30, profile, goals, metricsAsc, workoutsAsc, lastMeal, fastingPrefs] = await Promise.all([
    dietDb.fetchRecentDietSnapshots(29, now),
    dietDb.fetchDietProfile(),
    dietDb.fetchDietGoals(),
    dietDb.fetchAllMetrics(),
    dietDb.fetchAllWorkouts(),
    dietDb.fetchLastMeal(),
    dietDb.fetchFastingPrefs(),
  ]);
  const sevenDay = snapshots30.slice(0, 7);
  return {
    now,
    snapshots30,
    sevenDay,
    today: snapshots30[0],
    profile,
    goals,
    metricsAsc,
    workoutsAsc,
    lastMeal,
    fastingPrefs,
    avgDailyIntakeKcal: dietRead.averageDailyKcal(sevenDay),
  };
}

function fastingStatusFromContext(ctx: DietGatewayContext, previewHours: number | null = null) {
  return dietRead.fastingStatus({
    now: ctx.now,
    previewHours,
    prefs: ctx.fastingPrefs,
    healthReferenceInput: {
      now: ctx.now,
      metricsAsc: ctx.metricsAsc,
      workoutsAsc: ctx.workoutsAsc,
      lastMeal: ctx.lastMeal,
      profile: ctx.profile,
      avgDailyIntakeKcal: ctx.avgDailyIntakeKcal,
    },
  });
}

function dashboardFromContext(ctx: DietGatewayContext) {
  return dietRead.dashboard({
    goals: ctx.goals,
    today: ctx.today,
    sevenDaySnapshots: ctx.sevenDay,
    profile: ctx.profile,
    metricsAsc: ctx.metricsAsc,
    fastingPrefs: ctx.fastingPrefs,
  });
}

/** 원본 DietStore.planProjection() — diet.plan/profile.set/fasting.start가 공유하는 접미사 3종 로직. */
async function computePlanProjection(profileOverride?: dietRead.Profile | null): Promise<dietRead.PlanProjection | null> {
  const profile = profileOverride !== undefined ? profileOverride : await dietDb.fetchDietProfile();
  if (!profile || !dietRead.profileIsComplete(profile)) return null;
  const [goals, metricsAsc, sevenDay, fastingPrefs] = await Promise.all([
    dietDb.fetchDietGoals(),
    dietDb.fetchAllMetrics(),
    dietDb.fetchRecentDietSnapshots(6),
    dietDb.fetchFastingPrefs(),
  ]);
  const pick = dietRead.weightForPlan(metricsAsc);
  const planProfile = pick ? { ...profile, weightKg: pick.kg } : profile;
  const avg = dietRead.averageDailyKcal(sevenDay);
  return dietRead.planProjectionWithSuffixes(
    planProfile,
    avg,
    goals.targetKcal,
    Boolean(fastingPrefs.active),
    fastingPrefs.targetHours,
    pick?.isReferenceOnly ?? false,
  );
}

export async function diet_dashboard() {
  const ctx = await fetchDietGatewayContext();
  const dash = dashboardFromContext(ctx);
  const fasting = fastingStatusFromContext(ctx);
  return dietRead.dashboardDict(dash, fasting);
}

export async function diet_fasting_status(params: unknown) {
  const p = (params ?? {}) as { preview_hours?: number; target_hours?: number };
  const previewH =
    typeof p.preview_hours === "number" ? p.preview_hours : typeof p.target_hours === "number" ? p.target_hours : null;
  const ctx = await fetchDietGatewayContext();
  return fastingStatusFromContext(ctx, previewH);
}

export async function diet_fasting_preview(params: unknown) {
  const p = (params ?? {}) as { target_hours?: number; hours?: number };
  const hours = typeof p.target_hours === "number" ? p.target_hours : typeof p.hours === "number" ? p.hours : 14;
  const now = new Date();
  return dietRead.fastingEndPreview(hours, now, now);
}

export async function diet_fasting_start(params: unknown) {
  const p = (params ?? {}) as { target_hours?: number; hours?: number };
  const hours = typeof p.target_hours === "number" ? p.target_hours : typeof p.hours === "number" ? p.hours : null;
  const session = await dietDb.startFast(hours);
  const out = (await diet_fasting_status({})) as Record<string, unknown>;
  out.session = { id: session.id, started_at: session.startedAt, target_hours: session.targetHours };
  const plan = await computePlanProjection();
  if (plan) out.plan = dietRead.planProjectionDict(plan);
  return out;
}

export async function diet_fasting_end(params: unknown) {
  const p = (params ?? {}) as { reason?: string };
  await dietDb.endFast(typeof p.reason === "string" ? p.reason : "manual", new Date());
  return diet_fasting_status({});
}

export async function diet_plan() {
  const profile = await dietDb.fetchDietProfile();
  if (!profile || !dietRead.profileIsComplete(profile)) {
    return {
      needs_profile: true,
      eta_text: "키·몸무게·나이·성별·목표 체중을 입력하면 도달 시점을 계산해요.",
      plan_uses_ai: false,
      engine: "diet-rules/mifflin-7700",
    };
  }
  const plan = await computePlanProjection(profile);
  return dietRead.planProjectionDict(plan!);
}

export async function diet_coach(params: unknown) {
  const p = (params ?? {}) as { message?: string };
  const ctx = await fetchDietGatewayContext();
  const dash = dashboardFromContext(ctx);
  const lines = [...dash.analysisLines];
  const sleepHint = dietRead.sleepCoachHint(dietRead.latestSleepHours(ctx.sevenDay.slice(0, 3)));
  if (sleepHint) lines.push(sleepHint);
  const streak = dietRead.activityStreak(ctx.snapshots30);
  if (streak > 0) lines.push(`연속 기록 ${streak}일`);
  const msg = typeof p.message === "string" ? p.message.trim() : "";
  if (msg) lines.push(`질문 메모: ${msg}`);
  return {
    answer: lines.join("\n"),
    engine: "diet-rules/v1",
    day: dietRead.daySummaryDict(ctx.today),
    progress: {
      kcal: dash.kcalProgress,
      protein: dash.proteinProgress,
      workout: dash.workoutProgress,
      weekly_workouts: dash.weeklyWorkoutProgress,
    },
    streak_days: streak,
  };
}

export async function diet_suggest() {
  const now = new Date();
  const [today] = await dietDb.fetchRecentDietSnapshots(0, now);
  const s = dietRead.suggestedAction(now, today);
  const out: Record<string, unknown> = { title: s.title, subtitle: s.subtitle };
  if (s.slot) out.slot = s.slot;
  return out;
}

export async function diet_goals_set(params: unknown) {
  const p = (params ?? {}) as Record<string, unknown>;
  const g = await dietDb.fetchDietGoals();
  const next: dietRead.Goals = {
    targetKcal: typeof p.target_kcal === "number" ? p.target_kcal : g.targetKcal,
    targetProteinG: typeof p.target_protein_g === "number" ? p.target_protein_g : g.targetProteinG,
    weeklyWorkouts: typeof p.weekly_workouts === "number" ? p.weekly_workouts : g.weeklyWorkouts,
    targetWorkoutMinutesPerDay:
      typeof p.target_workout_minutes_per_day === "number" ? p.target_workout_minutes_per_day : g.targetWorkoutMinutesPerDay,
  };
  await dietDb.setDietGoals(next);
  return dietRead.goalsDict(next);
}

const ACTIVITIES: dietRead.Activity[] = ["sedentary", "light", "moderate", "active"];

export async function diet_profile_set(params: unknown) {
  const p = (params ?? {}) as Record<string, unknown>;
  const sex: dietRead.Sex = p.sex === "male" ? "male" : "female";
  const activity: dietRead.Activity = ACTIVITIES.includes(p.activity as dietRead.Activity)
    ? (p.activity as dietRead.Activity)
    : "light";
  const profile: dietRead.Profile = {
    heightCm: typeof p.height_cm === "number" ? p.height_cm : 165,
    weightKg: typeof p.weight_kg === "number" ? p.weight_kg : 65,
    age: typeof p.age === "number" ? p.age : 30,
    sex,
    targetWeightKg: typeof p.target_weight_kg === "number" ? p.target_weight_kg : 60,
    activity,
  };
  await dietDb.setDietProfile(profile);
  const applyGoals = typeof p.apply_goals === "boolean" ? p.apply_goals : true;
  const goals = applyGoals ? await dietDb.applyRecommendedGoalsFromProfile(profile) : await dietDb.fetchDietGoals();
  const out: Record<string, unknown> = { ...dietRead.profileDict(profile), goals: dietRead.goalsDict(goals) };
  const plan = await computePlanProjection(profile);
  if (plan) out.plan = dietRead.planProjectionDict(plan);
  return out;
}

function stringParam(v: unknown): string {
  return typeof v === "string" ? v : "";
}

export async function diet_log_meal(params: unknown) {
  const p = (params ?? {}) as { items?: unknown; note?: string; kcal?: number; protein_g?: number; proteinG?: number };
  let items: string[];
  if (Array.isArray(p.items)) items = p.items as string[];
  else if (typeof p.items === "string") items = [p.items];
  else if (typeof p.note === "string" && p.note) items = [p.note];
  else items = ["meal"];
  const meal = await dietDb.insertMeal({
    items,
    kcal: typeof p.kcal === "number" ? p.kcal : null,
    proteinG: typeof p.protein_g === "number" ? p.protein_g : typeof p.proteinG === "number" ? p.proteinG : null,
    note: typeof p.note === "string" ? p.note : null,
  });
  const out: Record<string, unknown> = { id: meal.id, ts: meal.ts, items: meal.items };
  if (meal.kcal != null) out.kcal = meal.kcal;
  if (meal.proteinG != null) out.protein_g = meal.proteinG;
  if (meal.note != null) out.note = meal.note;
  return out;
}

export async function diet_log_workout(params: unknown) {
  const p = (params ?? {}) as { kind?: string; minutes?: number; intensity?: string };
  const w = await dietDb.insertWorkout({
    kind: typeof p.kind === "string" ? p.kind : "workout",
    minutes: typeof p.minutes === "number" ? p.minutes : 0,
    intensity: typeof p.intensity === "string" ? p.intensity : null,
  });
  return { id: w.id, ts: w.ts, kind: w.kind, minutes: w.minutes };
}

export async function diet_log_metric(params: unknown) {
  const p = (params ?? {}) as {
    context?: string; morning_fasted?: boolean; weight_kg?: number; weightKg?: number; sleep_h?: number; sleepH?: number;
  };
  const ctx = typeof p.context === "string" ? p.context : p.morning_fasted === true ? "morning_fasted" : null;
  const m = await dietDb.insertMetric({
    weightKg: typeof p.weight_kg === "number" ? p.weight_kg : typeof p.weightKg === "number" ? p.weightKg : null,
    sleepH: typeof p.sleep_h === "number" ? p.sleep_h : typeof p.sleepH === "number" ? p.sleepH : null,
    context: ctx,
  });
  const out: Record<string, unknown> = { id: m.id, ts: m.ts };
  if (m.weightKg != null) out.weight_kg = m.weightKg;
  if (m.sleepH != null) out.sleep_h = m.sleepH;
  if (m.context != null) out.context = m.context;
  return out;
}

export async function diet_delete_meal(params: unknown) {
  const id = stringParam((params as { id?: unknown })?.id);
  if (!id) throw new Error("diet.delete_meal: missing id");
  const removed = await dietDb.deleteMeal(id);
  return { deleted: removed, id };
}

export async function diet_delete_workout(params: unknown) {
  const id = stringParam((params as { id?: unknown })?.id);
  if (!id) throw new Error("diet.delete_workout: missing id");
  const removed = await dietDb.deleteWorkout(id);
  return { deleted: removed, id };
}

export async function diet_delete_metric(params: unknown) {
  const id = stringParam((params as { id?: unknown })?.id);
  if (!id) throw new Error("diet.delete_metric: missing id");
  const removed = await dietDb.deleteMetric(id);
  return { deleted: removed, id };
}

/**
 * 원본 diet.json은 파일 SoT 전체 덤프(디버그 전용) — 액션플랜이 "디버그 전용으로
 * 축소"를 명시적으로 허용해 1:1 이식 대신 최소 상태 요약만 반환한다.
 */
export async function diet_json() {
  const goals = await dietDb.fetchDietGoals();
  const profile = await dietDb.fetchDietProfile();
  return {
    debug: true,
    goals: dietRead.goalsDict(goals),
    profile: profile ? dietRead.profileDict(profile) : null,
  };
}
