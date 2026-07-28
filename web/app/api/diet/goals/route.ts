import { NextResponse } from "next/server";
import { diet_goals } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await diet_goals());
}
