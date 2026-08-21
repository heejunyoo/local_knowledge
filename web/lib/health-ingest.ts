// Swift 원본: DietStore.ingestHealthSamples(_:) 1:1. `/api/health/ingest`
// 전용 — 세션 없는 정적 Bearer 토큰(INGEST_API_TOKEN) 인증이라 RLS
// (owner_id = auth.uid())를 통과할 방법이 없다. 오너 승인으로 이 파일에
// 한해서만 SUPABASE_SERVICE_ROLE_KEY로 RLS를 우회하고 owner_id를 코드에서
// 명시적으로 고정한다 — 이 예외를 다른 파일로 넓히지 말 것(docs/ENV_VARS.md).
import { createClient } from "@supabase/supabase-js";
import { DB_SCHEMA } from "@/lib/supabase/schema";

// docs/ENV_VARS.md·REFACTOR_STATUS.md에 기록된 오너 auth.uid() 고정값.
const OWNER_ID = "47e5b22d-a1f1-4266-b4e5-cd2524b0a37f";

function serviceClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    db: { schema: DB_SCHEMA },
  });
}

export interface IngestSample {
  client_id?: unknown;
  type?: unknown;
  ts?: unknown;
  source?: unknown;
  kind?: unknown;
  minutes?: unknown;
  weight_kg?: unknown;
  weightKg?: unknown;
  sleep_h?: unknown;
  sleepH?: unknown;
  /** 하루 종일 커지는 누적 스냅샷 — dedupe 대신 upsert 경로를 탄다(D-M). */
  steps?: unknown;
  active_energy_kcal?: unknown;
  activeEnergyKcal?: unknown;
}

export function parseIngestNumber(v: unknown): number | null {
  if (typeof v === "number") return v;
  if (typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v))) return Number(v);
  return null;
}

export function parseIngestTs(v: unknown): Date {
  if (typeof v === "string") {
    const d = new Date(v);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return new Date();
}

/** 원본: intensity = source=="healthkit" ? "healthkit" : source */
export function resolveIntensity(source: string): string {
  return source === "healthkit" ? "healthkit" : source;
}

type ServiceClient = ReturnType<typeof serviceClient>;

async function isFastingActive(supabase: ServiceClient): Promise<boolean> {
  const { data, error } = await supabase
    .from("settings")
    .select("value")
    .eq("owner_id", OWNER_ID)
    .eq("key", "diet.fasting")
    .maybeSingle();
  if (error) throw error;
  const prefs = data?.value as { active?: { ended_at: string | null } | null } | null;
  return Boolean(prefs?.active && prefs.active.ended_at == null);
}

/** 원본 logMetric()의 프로필 weightKg 동기화 부작용. */
async function syncProfileWeight(supabase: ServiceClient, weightKg: number): Promise<void> {
  const { data, error } = await supabase
    .from("settings")
    .select("value")
    .eq("owner_id", OWNER_ID)
    .eq("key", "diet.profile")
    .maybeSingle();
  if (error) throw error;
  if (!data?.value) return;
  const profile = data.value as Record<string, unknown>;
  const { error: upErr } = await supabase.from("settings").upsert({
    owner_id: OWNER_ID,
    key: "diet.profile",
    value: { ...profile, weight_kg: weightKg },
    updated_at: new Date().toISOString(),
  });
  if (upErr) throw upErr;
}

export interface IngestResult {
  accepted: number;
  deduped: number;
  received: number;
  errors?: string[];
}

/**
 * 원본 ingestHealthSamples(_:) 1:1 + D-M 확장. client_id 기준 idempotent —
 * 이미 존재하는 id는 deduped로 집계하고 재삽입하지 않는다. metric은
 * weight_kg/sleep_h/steps/active_energy_kcal 중 최소 하나 필요. steps·
 * active_energy_kcal이 있는 샘플은 하루 종일 커지는 누적 스냅샷이라 예외적으로
 * dedupe 대신 upsert로 갱신한다(같은 client_id 재전송이 정상) — weight_kg·
 * sleep_h만 있는 샘플의 dedupe 계약은 그대로다. HealthKit metric의 context는
 * 항상 "healthkit"(사용자 아침 공복 스케일과 절대 섞이지 않게 하는 원본의 핵심
 * 계약) — source가 healthkit이 아닐 때만 활성 단식 여부로 "morning_fasted"
 * 자동 태깅.
 */
export async function ingestHealthSamples(samples: IngestSample[]): Promise<IngestResult> {
  const supabase = serviceClient();
  let accepted = 0;
  let deduped = 0;
  const errors: string[] = [];

  for (let idx = 0; idx < samples.length; idx++) {
    const s = samples[idx];
    const clientId = typeof s.client_id === "string" ? s.client_id.trim() : "";
    if (!clientId) {
      errors.push(`[${idx}] missing client_id`);
      continue;
    }
    const type = typeof s.type === "string" ? s.type.toLowerCase() : "";
    const ts = parseIngestTs(s.ts);
    const source = typeof s.source === "string" ? s.source.toLowerCase() : "healthkit";

    try {
      if (type === "workout") {
        const { data: existing, error } = await supabase
          .from("diet_workout")
          .select("id")
          .eq("id", clientId)
          .maybeSingle();
        if (error) throw error;
        if (existing) {
          deduped++;
          continue;
        }
        const minutes = Math.max(0, Math.trunc(parseIngestNumber(s.minutes) ?? 0));
        const { error: insErr } = await supabase.from("diet_workout").insert({
          id: clientId,
          owner_id: OWNER_ID,
          ts: ts.toISOString(),
          kind: typeof s.kind === "string" && s.kind ? s.kind : "workout",
          minutes,
          intensity: resolveIntensity(source),
        });
        if (insErr) throw insErr;
        accepted++;
      } else if (type === "metric") {
        const weightKg = parseIngestNumber(s.weight_kg ?? s.weightKg);
        const sleepH = parseIngestNumber(s.sleep_h ?? s.sleepH);
        const steps = parseIngestNumber(s.steps);
        const activeEnergyKcal = parseIngestNumber(s.active_energy_kcal ?? s.activeEnergyKcal);
        if (weightKg == null && sleepH == null && steps == null && activeEnergyKcal == null) {
          errors.push(`[${idx}] metric needs weight_kg, sleep_h, steps, or active_energy_kcal`);
          continue;
        }
        // 누적 스냅샷이 아닌 기존 경로는 **dedupe 를 먼저 본다.** 중복이면 여기서 끝나야
        // 원래처럼 isFastingActive() 조회를 타지 않는다 — 순서를 바꾸면 중복 재전송마다
        // settings 를 한 번씩 더 읽고, 그 조회가 실패할 때 원래는 deduped 였을 샘플이
        // 에러로 뒤집힌다.
        const cumulative = steps != null || activeEnergyKcal != null;
        if (!cumulative) {
          const { data: existing, error } = await supabase
            .from("diet_metric")
            .select("id")
            .eq("id", clientId)
            .maybeSingle();
          if (error) throw error;
          if (existing) {
            deduped++;
            continue;
          }
        }

        let context: string | null = source === "healthkit" ? "healthkit" : null;
        if (context == null && weightKg != null && (await isFastingActive(supabase))) {
          context = "morning_fasted";
        }
        const row = {
          id: clientId,
          owner_id: OWNER_ID,
          ts: ts.toISOString(),
          weight_kg: weightKg,
          sleep_h: sleepH,
          steps,
          active_energy_kcal: activeEnergyKcal,
          context,
        };

        // steps·active_energy_kcal은 그 시점까지의 누적 스냅샷이다(D-M) — 단축어가
        // 같은 client_id(예: steps-2026-08-20)로 하루 종일 재전송하는 것이 정상 동작
        // 이라 dedupe로 버리면 값이 절대 갱신되지 않는다. syncProfileWeight와 같은
        // upsert 방식으로 최신값을 덮어쓴다. weight_kg·sleep_h만 있는 샘플(하루 한
        // 번 찍는 값)은 기존 idempotent 계약(이미 있으면 deduped++, 재삽입 안 함)을
        // 그대로 유지한다 — 반환 집계의 의미를 바꾸지 않는다.
        if (cumulative) {
          const { error: upErr } = await supabase.from("diet_metric").upsert(row);
          if (upErr) throw upErr;
        } else {
          const { error: insErr } = await supabase.from("diet_metric").insert(row);
          if (insErr) throw insErr;
        }
        if (weightKg != null) await syncProfileWeight(supabase, weightKg);
        accepted++;
      } else {
        errors.push(`[${idx}] unknown type ${type}`);
      }
    } catch (e) {
      errors.push(`[${idx}] ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  const out: IngestResult = { accepted, deduped, received: samples.length };
  if (errors.length > 0) out.errors = errors;
  return out;
}
