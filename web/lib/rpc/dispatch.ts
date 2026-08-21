import * as h from "./handlers";

type Handler = (params: unknown) => Promise<unknown>;

// P4a 스코프: 읽기 전용 + D-3 상태기계 쓰기(inbox.promote/corpus.sync/
// search.reindex, task 9). diet 쓰기 등 나머지는 P4b에서 추가된다.
const REGISTRY: Record<string, Handler> = {
  "core.ping": h.core_ping,
  "core.services": h.core_services,
  "core.health": h.core_health,
  "assistant.today": h.assistant_today,
  "assistant.week_review": h.assistant_week_review,
  "assistant.gaps": h.assistant_gaps,
  "timeline.list": h.timeline_list,
  "diet.day_summary": h.diet_day_summary,
  "diet.week_review": h.diet_week_review,
  "diet.goals": h.diet_goals,
  "diet.goals.get": h.diet_goals,
  "diet.profile.get": h.diet_profile_get,
  "diet.profile.set": h.diet_profile_set,
  "diet.ping": h.diet_ping,
  "diet.estimate_nutrition": h.diet_estimate_nutrition,
  "diet.dashboard": h.diet_dashboard,
  "diet.fasting.status": h.diet_fasting_status,
  "diet.fasting.preview": h.diet_fasting_preview,
  "diet.fasting.start": h.diet_fasting_start,
  "diet.fasting.end": h.diet_fasting_end,
  "diet.plan": h.diet_plan,
  "day.grade": h.day_grade,
  "diet.coach": h.diet_coach,
  "diet.suggest": h.diet_suggest,
  "diet.goals.set": h.diet_goals_set,
  "diet.log_meal": h.diet_log_meal,
  "diet.search_product": h.diet_search_product,
  "diet.preview_product": h.diet_preview_product,
  "diet.log_product_meal": h.diet_log_product_meal,
  "diet.log_workout": h.diet_log_workout,
  "diet.log_metric": h.diet_log_metric,
  "diet.delete_meal": h.diet_delete_meal,
  "diet.delete_workout": h.diet_delete_workout,
  "diet.delete_metric": h.diet_delete_metric,
  "diet.json": h.diet_json,
  "knowledge.health": h.knowledge_health,
  "knowledge.search": h.knowledge_search,
  "knowledge.ask": h.knowledge_ask,
  "knowledge.ask.fast": h.knowledge_ask_fast,
  "chat.send": h.chat_send,
  "corpus.status": h.corpus_status,
  "corpus.sync": h.corpus_sync,
  "search.reindex": h.search_reindex,
  "inbox.list": h.inbox_list,
  "inbox.create": h.inbox_create,
  "inbox.promote": h.inbox_promote,
  "health.sync_status": h.health_sync_status,
};

export interface RpcError {
  code: number;
  message: string;
}

export interface RpcOutcome {
  result?: unknown;
  error?: RpcError;
}

export async function dispatch(method: string, params: unknown): Promise<RpcOutcome> {
  const handler = REGISTRY[method];
  if (!handler) {
    return { error: { code: -32601, message: "method not found" } };
  }
  const result = await handler(params);
  return { result };
}
