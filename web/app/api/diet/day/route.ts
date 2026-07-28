import { NextResponse } from "next/server";
import { diet_day_summary } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await diet_day_summary());
}
