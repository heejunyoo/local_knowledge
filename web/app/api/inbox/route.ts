import { NextRequest, NextResponse } from "next/server";
import { inbox_list, inbox_create } from "@/lib/rpc/handlers";

export async function GET(request: NextRequest) {
  const includePromoted = request.nextUrl.searchParams.get("include_promoted") === "1";
  return NextResponse.json(await inbox_list({ include_promoted: includePromoted }));
}

export async function POST(request: NextRequest) {
  let body: { text?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  try {
    const item = await inbox_create(body);
    return NextResponse.json(item, { status: 201 });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "inbox.create failed" }, { status: 400 });
  }
}
