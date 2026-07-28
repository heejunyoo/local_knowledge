// Shortcuts(iOS)가 CRON_SECRET과 같은 방식으로 `Authorization: Bearer <INGEST_API_TOKEN>`을
// 붙여 호출한다. 미설정 시 명시적으로 먼저 걷어낸다 — lib/cron.ts의 CRON_SECRET
// 구멍(`Bearer undefined` 리터럴 통과)과 동일한 이유로.
export function isIngestAuthorized(authHeader: string | null): boolean {
  const token = process.env.INGEST_API_TOKEN;
  if (!token) return false;
  return authHeader === `Bearer ${token}`;
}
