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
  "diet.ping": h.diet_ping,
  "diet.estimate_nutrition": h.diet_estimate_nutrition,
  "knowledge.health": h.knowledge_health,
  "knowledge.search": h.knowledge_search,
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
