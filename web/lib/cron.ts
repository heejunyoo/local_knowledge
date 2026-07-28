// Vercel Cron이 CRON_SECRET 환경변수가 설정돼 있으면 자동으로
// `Authorization: Bearer <CRON_SECRET>`을 붙여 호출한다(대시보드 Cron Jobs 문서).
// CRON_SECRET을 명시적으로 먼저 확인한다 — 그냥 문자열 비교만 하면 미설정 시
// `Bearer undefined`라는 리터럴 헤더값이 우연히 통과해버리는 구멍이 생긴다.
export function isCronAuthorized(authHeader: string | null): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return authHeader === `Bearer ${secret}`;
}
