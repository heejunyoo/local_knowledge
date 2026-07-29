import { NextRequest, NextResponse } from "next/server";
import { isCronAuthorized } from "@/lib/cron";
import { sendFastingReminderEmail } from "@/lib/email/resend";

// pg_cron이 net.http_post로 호출한다(web/supabase/migrations/006_fasting_reminder_cron.sql).
// goal_met 판정과 reminder_sent_at 기록은 그 SQL 함수(SECURITY DEFINER) 안에서 처리되고,
// 이 라우트는 DB에 전혀 접근하지 않는 순수 발송기다 — health-ingest.ts에만 한정된
// SUPABASE_SERVICE_ROLE_KEY 예외를 여기로 확장하지 않기 위한 설계(docs/ENV_VARS.md).
export async function POST(request: NextRequest) {
  if (!isCronAuthorized(request.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as {
    to?: unknown;
    target_hours?: unknown;
    elapsed_hours?: unknown;
  } | null;

  const to = typeof body?.to === "string" ? body.to : "";
  const targetHours = Number(body?.target_hours);
  const elapsedHours = Number(body?.elapsed_hours);
  if (!to || !Number.isFinite(targetHours) || !Number.isFinite(elapsedHours)) {
    return NextResponse.json({ error: "invalid body" }, { status: 400 });
  }

  const result = await sendFastingReminderEmail({ to, targetHours, elapsedHours });
  return NextResponse.json(result);
}
