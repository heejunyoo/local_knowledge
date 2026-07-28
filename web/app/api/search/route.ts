import { NextRequest, NextResponse } from "next/server";
import { knowledge_search } from "@/lib/rpc/handlers";

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q") ?? "";
  const limitParam = request.nextUrl.searchParams.get("limit");
  const limit = limitParam ? Number(limitParam) : undefined;
  return NextResponse.json(await knowledge_search({ q, limit }));
}
