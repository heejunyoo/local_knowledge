import { NextResponse } from "next/server";
import { diet_week_review } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await diet_week_review());
}
