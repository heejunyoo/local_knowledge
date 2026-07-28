// G4a-1: 읽기 메서드 전부 → 정규화 후 P0 골든과 diff 0.
// 실행: npm run test:regression (실제 Supabase 프로젝트 필요, web/.env.local).
import { describe, it, expect, vi, beforeAll, afterAll } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { normalize } from "./normalize";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { dispatch } = await import("@/lib/rpc/dispatch");

const GOLDEN_DIR = path.join(__dirname, "..", "golden", "read");
const METHODS = fs.readdirSync(GOLDEN_DIR).map((f) => f.replace(/\.json$/, ""));

// 아직 구현되지 않은 라우트 — 각자의 phase 완료 후 이 목록에서 뺀다.
const NOT_YET_IMPLEMENTED = new Set([
  "diet.dashboard", // P4a-12(별도 세션): Mifflin 플랜 투영·HealthKit 참고값·요일상대 문구
  "diet.fasting.status", // P4a-12(별도 세션): 위와 동일 엔진 의존
]);

// 문서화된 diff-0 예외 — REFACTOR_STATUS.md "P4a 진행 상황" §1 참고.
// Mac 로컬 데몬 필드(db_path 등)는 Vercel에 존재하지 않아 축소된 필드만 비교한다.
// core.health의 golden.diet.totals는 전부 `false`다(0이어야 할 자리) — 원본
// Swift가 [String:Any] 딕셔너리를 core.health 경로에서만 두 번 JSONSerialization
// 왕복시키며 생긴 Double 0.0 → NSNumber(bool:false) 브리징 버그로 보인다.
// diet.day_summary 골든(같은 daySummaryDict 함수, 0으로 정상 캡처됨)이 이미
// 올바른 값을 검증하므로, core.health에서는 diet를 비교 대상에서 뺀다 —
// 버그를 재현하는 게 아니라 정확한 값을 반환하는 쪽을 택했다.
const REDUCED_FIELD_EXCEPTIONS: Record<string, string[]> = {
  "core.health": ["ok", "services"],
  "knowledge.health": ["ok"],
};

// corpus.status는 P1 이관 이후 실제 vault 구성(F-1 미팅 소스 제외 등)이 골든
// 캡처 시점과 달라 값 자체가 어긋난다(docs/REFACTOR_BACKLOG.md "P4a에서 발견").
// 구조(키 존재)만 확인하고 값 diff-0 비교는 하지 않는다.
const STRUCTURAL_ONLY = new Set(["corpus.status"]);

beforeAll(() => {
  // 골든 캡처 시각대(2026-07-27, KST 저녁 — assistant.gaps/today의 시간대별
  // 분기가 재현되려면 이 창 안이어야 한다)로 시계를 고정한다. 이 계정의
  // diet 데이터가 전 기간 0건이라 어느 날짜를 고르든 무관하지만, diet.week_review
  // 의 from/to는 정규화 대상이 아니라(normalize.py VOLATILE_KEYS에 없음) 골든의
  // "2026-07-21"~"2026-07-27"과 문자 그대로 일치해야 한다.
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-07-27T09:00:00Z")); // = 18:00 KST
});

afterAll(() => {
  vi.useRealTimers();
});

describe.each(METHODS)("G4a-1 골든 회귀: %s", (method) => {
  const golden = JSON.parse(fs.readFileSync(path.join(GOLDEN_DIR, `${method}.json`), "utf-8"));

  it.skipIf(NOT_YET_IMPLEMENTED.has(method))("정규화 후 diff 0", async () => {
    const outcome = await dispatch(method, {});
    if (outcome.error) {
      throw new Error(`${method} → RPC error ${outcome.error.code}: ${outcome.error.message}`);
    }

    const actual = normalize(outcome.result) as Record<string, unknown>;
    const expected = normalize(golden.result) as Record<string, unknown>;

    if (STRUCTURAL_ONLY.has(method)) {
      expect(Object.keys(actual).sort()).toEqual(Object.keys(expected).sort());
      return;
    }

    const allow = REDUCED_FIELD_EXCEPTIONS[method];
    if (allow) {
      for (const key of allow) {
        expect(actual[key], `${method}.${key}`).toEqual(expected[key]);
      }
      return;
    }

    expect(actual).toEqual(expected);
  });
});
