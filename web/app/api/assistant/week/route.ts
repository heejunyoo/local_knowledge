import { NextResponse } from "next/server";
import { assistant_week_review } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await assistant_week_review());
}
