import { NextResponse } from "next/server";
import { diet_profile_get } from "@/lib/rpc/handlers";

export async function GET() {
  return NextResponse.json(await diet_profile_get());
}
