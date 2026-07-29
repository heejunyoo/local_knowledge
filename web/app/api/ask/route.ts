import { NextRequest, NextResponse } from "next/server";
import { knowledge_ask, knowledge_ask_fast } from "@/lib/rpc/handlers";

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
