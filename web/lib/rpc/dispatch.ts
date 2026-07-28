import * as h from "./handlers";

type Handler = (params: unknown) => Promise<unknown>;

// P4a 스코프: 읽기 전용. knowledge/corpus/inbox(P4a-6), 상태기계가 필요한
// 쓰기 메서드(P4a-9)는 여기에 추가되기 전까지 method not found로 거부된다.
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
