import { NextRequest, NextResponse } from "next/server";
import { chat_send } from "@/lib/rpc/handlers";

/**
 * Vercel Hobby 는 함수가 기본 10초에서 잘린다(최대 60초까지만 올릴 수 있다 —
 * https://vercel.com/docs/limits). 이 경로는 LLM 을 부르므로(chat_send 가 rag.refine 으로 LLM 을 부른다) 10초는 경계 위다.
 * 근거: docs/PLATFORM_DECISION_2026-08.md §2.2 · F-3.
 */
export const maxDuration = 60;

/** 원본 MobileHTTPServer `POST /v1/chat` 대응. */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as { message?: string; mode?: string };
  return NextResponse.json(await chat_send(body));
}
