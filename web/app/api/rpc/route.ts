import { NextRequest, NextResponse } from "next/server";
import { dispatch } from "@/lib/rpc/dispatch";

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
