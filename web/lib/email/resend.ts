// G4b-4(단식 리마인더 실제 발화) 전용, 2026-07-29 오너 결정: 이메일 채널.
// Resend REST API를 fetch로 직접 호출한다(SDK 미설치 — 요청 1종뿐이라 SDK 불필요).
const RESEND_API_URL = "https://api.resend.com/emails";
const FROM_ADDRESS = "KnowledgeApp <onboarding@resend.dev>";

export interface FastingReminderEmailInput {
  to: string;
  targetHours: number;
  elapsedHours: number;
}

export interface SendEmailResult {
  sent: boolean;
  /** RESEND_API_KEY 미설정 등으로 스킵한 경우의 사유. 발송 성공 시 undefined. */
  skippedReason?: string;
}

/** RESEND_API_KEY 미설정 시 발송을 조용히 스킵(에러 아님) — 키 발급 전에도 크론이 안전하게 동작해야 한다. */
export async function sendFastingReminderEmail(
  input: FastingReminderEmailInput,
  fetchImpl: typeof fetch = fetch,
): Promise<SendEmailResult> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    return { sent: false, skippedReason: "RESEND_API_KEY not configured" };
  }

  const hours = Math.trunc(input.elapsedHours);
  const res = await fetchImpl(RESEND_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [input.to],
      subject: `단식 목표 ${Math.trunc(input.targetHours)}시간 달성했어요`,
      html: `<p>공복 ${hours}시간이 지나 목표 ${Math.trunc(input.targetHours)}시간을 채웠어요.</p>` +
        `<p>식사 창을 열거나 앱에서 「단식 종료」를 눌러주세요.</p>`,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`resend send failed: ${res.status} ${body}`);
  }
  return { sent: true };
}
