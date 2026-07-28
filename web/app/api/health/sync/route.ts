import { NextResponse } from "next/server";
import { health_sync_status } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await health_sync_status());
}
