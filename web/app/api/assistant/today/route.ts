import { NextResponse } from "next/server";
import { assistant_today } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await assistant_today());
}
