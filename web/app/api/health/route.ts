import { NextRequest, NextResponse } from "next/server";
import { core_health, core_ping } from "@/lib/rpc/handlers";

// core.ping의 REST 별칭. `?full=1`이면 core.health(§8)로 넘어간다.
export async function GET(request: NextRequest) {
  const full = request.nextUrl.searchParams.get("full") === "1";
  const result = full ? await core_health() : await core_ping();
  return NextResponse.json(result);
}
