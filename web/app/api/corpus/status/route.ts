import { NextResponse } from "next/server";
import { corpus_status } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await corpus_status());
}
