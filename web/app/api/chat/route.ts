import { NextRequest, NextResponse } from "next/server";
import { chat_send } from "@/lib/rpc/handlers";

/** 원본 MobileHTTPServer `POST /v1/chat` 대응. */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as { message?: string; mode?: string };
  return NextResponse.json(await chat_send(body));
}
