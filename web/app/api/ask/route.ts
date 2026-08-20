import { NextRequest, NextResponse } from "next/server";
import { knowledge_ask, knowledge_ask_fast } from "@/lib/rpc/handlers";

/**
 * Vercel Hobby 는 함수가 기본 10초에서 잘린다(최대 60초까지만 올릴 수 있다 —
 * https://vercel.com/docs/limits). 이 경로는 LLM 을 부르므로(knowledge_ask 가 LLM 캐스케이드를 탄다) 10초는 경계 위다.
 * 근거: docs/PLATFORM_DECISION_2026-08.md §2.2 · F-3.
 */
export const maxDuration = 60;

/** 원본 MobileHTTPServer `knowledge.ask`/`knowledge.ask.fast` REST 대응(액션플랜 §8: POST /api/ask). */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as {
    q?: string;
    question?: string;
    limit?: number;
    use_llama?: boolean;
    fast?: boolean;
  };
  const handler = body.fast ? knowledge_ask_fast : knowledge_ask;
  return NextResponse.json(await handler(body));
}
