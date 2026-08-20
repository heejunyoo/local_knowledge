import { NextRequest, NextResponse } from "next/server";
import { dispatch } from "@/lib/rpc/dispatch";

/**
 * Vercel Hobby 는 함수가 기본 10초에서 잘린다(최대 60초까지만 올릴 수 있다 —
 * https://vercel.com/docs/limits). 이 경로는 LLM 을 부르므로(dispatch 가 knowledge.ask · chat.send · diet.estimate_nutrition 에 모두 닿는다) 10초는 경계 위다.
 * 근거: docs/PLATFORM_DECISION_2026-08.md §2.2 · F-3.
 */
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  let body: { id?: unknown; method?: string; params?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const id = body.id ?? null;
  if (typeof body.method !== "string") {
    return NextResponse.json(
      { jsonrpc: "2.0", id, error: { code: -32600, message: "invalid request" } },
      { status: 400 },
    );
  }

  const outcome = await dispatch(body.method, body.params);
  if (outcome.error) {
    return NextResponse.json({ jsonrpc: "2.0", id, error: outcome.error });
  }
  return NextResponse.json({ jsonrpc: "2.0", id, result: outcome.result });
}
