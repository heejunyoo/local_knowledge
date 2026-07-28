// web/scripts/normalize.py의 1:1 이식 — 규칙은 web/tests/golden/NORMALIZE.md 참고.
//
// 한 가지 확장: ISO 타임스탬프 정규식이 원본은 `Z` 접미사만 인정한다(Swift
// ISO8601DateFormatter가 그렇게 찍었기 때문). Postgres timestamptz를
// supabase-js로 읽으면 `+00:00` 오프셋 형태로 온다 — 이것도 마스킹 대상이라
// 정규식을 오프셋까지 인정하도록 넓혔다. 마스킹 대상(휘발성 타임스탬프)이라는
// 의도는 원본과 동일하고, 우리 시스템의 실제 출력 형태에 맞춘 것뿐이다.
const ISO_TS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
const UUID_RE = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/g;
const DIGIT_RUN_RE = /\d+(\.\d+)?/g;

const VOLATILE_KEYS = new Set([
  "ts",
  "date",
  "updated_at",
  "created_at",
  "generated_at",
  "started_at",
  "ends_at",
  "starts_at",
  "heartbeat_at",
  "hours_since_last_meal",
]);

const RELATIVE_TEXT_KEYS = new Set([
  "starts_at_label",
  "ends_at_label",
  "detail_line",
  "preview_line",
  "hint",
  "summary",
  "summary_text",
  "lines",
]);

export function normalize(value: unknown, key: string | null = null): unknown {
  if (Array.isArray(value)) {
    return value.map((v) => normalize(v, key));
  }
  if (value !== null && typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const k of Object.keys(value as Record<string, unknown>).sort()) {
      sorted[k] = normalize((value as Record<string, unknown>)[k], k);
    }
    return sorted;
  }
  if (typeof value === "string") {
    if ((key && VOLATILE_KEYS.has(key)) || ISO_TS_RE.test(value)) {
      return "<TS>";
    }
    let v = value.replace(UUID_RE, "<UUID>");
    if (key && RELATIVE_TEXT_KEYS.has(key)) {
      v = v.replace(DIGIT_RUN_RE, "<N>");
    }
    return v;
  }
  if (typeof value === "number" && !Number.isInteger(value)) {
    if (key && VOLATILE_KEYS.has(key)) return "<N>";
    return Math.round(value * 100) / 100;
  }
  return value;
}
