import { describe, it, expect, vi, beforeEach } from "vitest";

// tests/domain/ingest.test.ts와 동일한 패턴: createClient()를 얇은 in-memory
// 쿼리 빌더로 mock한다. ingestHealthSamples가 SUPABASE_SERVICE_ROLE_KEY로
// "@supabase/supabase-js"의 createClient를 직접 부르기 때문에(이 파일만의
// 예외 — lib/health-ingest.ts 헤더 주석 참고), "@/lib/supabase/server"가
// 아니라 "@supabase/supabase-js" 자체를 mock한다.
type Row = Record<string, unknown>;

let metricRows: Row[] = [];
let workoutRows: Row[] = [];
let settingsRows: Row[] = [];

function tableStore(table: string): Row[] {
  if (table === "diet_metric") return metricRows;
  if (table === "diet_workout") return workoutRows;
  if (table === "settings") return settingsRows;
  throw new Error(`unexpected table ${table}`);
}

function makeBuilder(table: string) {
  const filters: [string, unknown][] = [];
  const builder: Record<string, unknown> = {
    select() {
      return builder;
    },
    eq(col: string, val: unknown) {
      filters.push([col, val]);
      return builder;
    },
    maybeSingle() {
      const rows = tableStore(table).filter((r) => filters.every(([c, v]) => r[c] === v));
      return Promise.resolve({ data: rows[0] ? { ...rows[0] } : null, error: null });
    },
    insert(payload: Row) {
      tableStore(table).push({ ...payload });
      return Promise.resolve({ error: null });
    },
    upsert(payload: Row) {
      const rows = tableStore(table);
      const matches =
        table === "settings"
          ? (r: Row) => r.owner_id === payload.owner_id && r.key === payload.key
          : (r: Row) => r.id === payload.id;
      const idx = rows.findIndex(matches);
      if (idx >= 0) rows[idx] = { ...rows[idx], ...payload };
      else rows.push({ ...payload });
      return Promise.resolve({ error: null });
    },
  };
  return builder;
}

const supabaseMock = {
  from(table: string) {
    return makeBuilder(table);
  },
};

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => supabaseMock),
}));

const { ingestHealthSamples, parseIngestNumber, parseIngestTs, resolveIntensity } = await import(
  "@/lib/health-ingest"
);

beforeEach(() => {
  metricRows = [];
  workoutRows = [];
  settingsRows = [];
});

describe("parseIngestNumber", () => {
  it("숫자는 그대로, 숫자 문자열은 변환, 그 외는 null", () => {
    expect(parseIngestNumber(3.5)).toBe(3.5);
    expect(parseIngestNumber("3.5")).toBe(3.5);
    expect(parseIngestNumber("")).toBeNull();
    expect(parseIngestNumber("abc")).toBeNull();
    expect(parseIngestNumber(undefined)).toBeNull();
    expect(parseIngestNumber(null)).toBeNull();
  });
});

describe("parseIngestTs", () => {
  it("유효한 ISO 문자열은 파싱하고, 없거나 무효하면 현재 시각으로 대체한다", () => {
    const d = parseIngestTs("2026-07-27T10:00:00Z");
    expect(d.toISOString()).toBe("2026-07-27T10:00:00.000Z");

    const before = Date.now();
    const fallback = parseIngestTs("not-a-date");
    expect(fallback.getTime()).toBeGreaterThanOrEqual(before);

    const fallback2 = parseIngestTs(undefined);
    expect(fallback2.getTime()).toBeGreaterThanOrEqual(before);
  });
});

describe("resolveIntensity", () => {
  it("healthkit이면 그대로, 아니면 source 문자열을 그대로 쓴다", () => {
    expect(resolveIntensity("healthkit")).toBe("healthkit");
    expect(resolveIntensity("garmin")).toBe("garmin");
  });
});

describe("ingestHealthSamples — 기존 dedupe 계약(weight_kg/sleep_h)", () => {
  it("같은 client_id를 재전송하면 재삽입하지 않고 deduped로 집계한다(idempotent)", async () => {
    const sample = { client_id: "m-1", type: "metric", ts: "2026-08-20T07:00:00Z", weight_kg: 70.2 };
    const first = await ingestHealthSamples([sample]);
    expect(first).toMatchObject({ accepted: 1, deduped: 0, received: 1 });
    expect(metricRows).toHaveLength(1);

    const second = await ingestHealthSamples([sample]);
    expect(second).toMatchObject({ accepted: 0, deduped: 1, received: 1 });
    expect(metricRows).toHaveLength(1); // 재삽입되지 않았다
  });

  it("sleep_h만 있는 샘플도 같은 dedupe 계약을 따른다", async () => {
    const sample = { client_id: "s-1", type: "metric", ts: "2026-08-20T23:00:00Z", sleep_h: 7.5 };
    await ingestHealthSamples([sample]);
    const result = await ingestHealthSamples([sample]);
    expect(result).toMatchObject({ accepted: 0, deduped: 1 });
    expect(metricRows).toHaveLength(1);
  });

  it("weight_kg·sleep_h 둘 다 없으면 에러로 집계하고 저장하지 않는다", async () => {
    const result = await ingestHealthSamples([{ client_id: "bad-1", type: "metric", ts: "2026-08-20T07:00:00Z" }]);
    expect(result.accepted).toBe(0);
    expect(result.errors?.[0]).toMatch(/metric needs/);
    expect(metricRows).toHaveLength(0);
  });
});

describe("ingestHealthSamples — steps·active_energy_kcal은 upsert로 갱신된다(D-M)", () => {
  it("같은 client_id로 steps를 재전송하면 dedupe로 버려지지 않고 값이 갱신된다", async () => {
    const dayId = "steps-2026-08-20";
    const first = await ingestHealthSamples([
      { client_id: dayId, type: "metric", ts: "2026-08-20T10:00:00Z", steps: 3000 },
    ]);
    expect(first).toMatchObject({ accepted: 1, deduped: 0 });
    expect(metricRows).toHaveLength(1);
    expect(metricRows[0].steps).toBe(3000);

    const second = await ingestHealthSamples([
      { client_id: dayId, type: "metric", ts: "2026-08-20T18:00:00Z", steps: 9500 },
    ]);
    // dedupe로 버려졌다면 accepted:0/deduped:1이었을 것 — upsert 경로는 accepted로 집계하고 갱신한다.
    expect(second).toMatchObject({ accepted: 1, deduped: 0 });
    expect(metricRows).toHaveLength(1); // 같은 행이 갱신됐지, 새 행이 추가되지 않았다
    expect(metricRows[0].steps).toBe(9500);
  });

  it("active_energy_kcal도 같은 client_id 재전송으로 갱신된다", async () => {
    const dayId = "active-energy-2026-08-20";
    await ingestHealthSamples([
      { client_id: dayId, type: "metric", ts: "2026-08-20T10:00:00Z", active_energy_kcal: 120 },
    ]);
    await ingestHealthSamples([
      { client_id: dayId, type: "metric", ts: "2026-08-20T18:00:00Z", active_energy_kcal: 480 },
    ]);
    expect(metricRows).toHaveLength(1);
    expect(metricRows[0].active_energy_kcal).toBe(480);
  });

  it("steps 하나만 와도(둘 다 없으면 에러 조건에 새 필드가 포함된다) accepted로 통과한다", async () => {
    const result = await ingestHealthSamples([
      { client_id: "steps-only", type: "metric", ts: "2026-08-20T10:00:00Z", steps: 500 },
    ]);
    expect(result).toMatchObject({ accepted: 1, deduped: 0 });
    expect(result.errors).toBeUndefined();
  });

  it("weight_kg와 steps가 같은 샘플에 섞여도 weight_kg는 결측 없이 함께 저장된다", async () => {
    await ingestHealthSamples([
      { client_id: "mixed-1", type: "metric", ts: "2026-08-20T10:00:00Z", weight_kg: 70, steps: 1200 },
    ]);
    expect(metricRows[0]).toMatchObject({ weight_kg: 70, steps: 1200 });
  });
});
