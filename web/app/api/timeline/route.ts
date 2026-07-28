import { NextResponse } from "next/server";
import { timeline_list } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await timeline_list());
}
