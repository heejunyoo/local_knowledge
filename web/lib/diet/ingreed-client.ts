// ingreed RPC(교차 프로젝트 Supabase) 호출 — 타임아웃·쿨다운·폴백 배선.
// nutrition-enrich.ts와 같은 모양: 오케스트레이터는 lib/diet/에 두고, fetch를
// 주입 가능한 인자로 받아 네트워크 없이 테스트한다. 키 없음·실패·타임아웃은
// 전부 에러가 아니라 폴백(null)이다 — G6-3 원칙.
//
// spec: .claude/specs/ingreed-diet-nutrition/spec.md §2, §4(D4, D6)
// - URL·anon key는 환경변수 INGREED_URL·INGREED_ANON_KEY로만 받는다(D4). 없으면
//   조용히 꺼지고 기존 경로(LLM 추정 폴백)로 넘어간다 — 에러로 보이면 안 된다.
// - 타임아웃 4초·실패 후 20초 쿨다운(D6). cold 실측이 2.97s라 여유가 좁지만,
//   실패해도 nutrition-enrich.ts의 LLM 추정 폴백이 있으므로 괜찮다.

export type FetchFn = typeof fetch;

/**
 * ⚠ 4000 이었다가 8000 으로 올렸다(2026-08-17). 실호출에서 **cold 첫 질의가 그대로
 * 폴백으로 떨어졌다** — 같은 질의가 warm 에서는 175ms 였다. ingreed 자신의 운영 기록도
 * 같은 말을 한다(~/ingreed/docs/NEXT.md): "캐시가 빈 상태에서는 첫 질의 하나가 4초를
 * 넘길 수 있는데 … 그 한 번으로 사용자가 폴백에 갇혔다."
 *
 * 4초는 그 경계 위가 아니라 **정확히 경계에** 있었다. 기성식품은 정답이 존재하는
 * 영역이라 폴백(LLM 추정)으로 떨어지는 것 자체가 손실이다 — 조회를 한 번 더 기다리는
 * 쪽이 낫다.
 */
const TIMEOUT_MS = 8000;
const COOLDOWN_MS = 20000;

/**
 * 모듈 스코프 쿨다운 상태. 서버리스 인스턴스 하나가 살아있는 동안만 유효하면
 * 되는 값이라 파일/DB 저장 없이 변수로 둔다(throttle.ts의 settings 저장과
 * 달리 여기는 "재시작하면 잊혀도 되는" 값). 테스트가 초기화할 수 있게 export.
 */
let cooldownUntil = 0;

export function resetCooldown(): void {
  cooldownUntil = 0;
}

function inCooldown(): boolean {
  return Date.now() < cooldownUntil;
}

function armCooldown(): void {
  cooldownUntil = Date.now() + COOLDOWN_MS;
}

interface IngreedEnv {
  url: string;
  anonKey: string;
}

/** 없으면 null — 조용히 꺼진다(D4). 값이 있는지만 볼 뿐 형식을 검증하지 않는다. */
function readEnv(): IngreedEnv | null {
  const url = process.env.INGREED_URL?.trim();
  const anonKey = process.env.INGREED_ANON_KEY?.trim();
  if (!url || !anonKey) return null;
  return { url: url.replace(/\/+$/, ""), anonKey };
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("ingreed-timeout")), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

/**
 * 공통 RPC 호출. 쿨다운 중이거나 환경변수가 없으면 fetchFn을 부르지도 않고
 * null을 반환한다. HTTP 실패·예외(타임아웃 포함)는 쿨다운을 걸고 null.
 * 성공하면 쿨다운을 해제한다.
 */
async function callRpc<T>(fn: string, args: Record<string, unknown>, fetchFn: FetchFn): Promise<T | null> {
  if (inCooldown()) return null;

  const env = readEnv();
  if (!env) return null;

  try {
    const res = await withTimeout(
      fetchFn(`${env.url}/rest/v1/rpc/${fn}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: env.anonKey,
          Authorization: `Bearer ${env.anonKey}`,
        },
        body: JSON.stringify(args),
      }),
      TIMEOUT_MS,
    );

    if (!res.ok) {
      armCooldown();
      return null;
    }

    const data = (await res.json()) as T;
    cooldownUntil = 0;
    return data;
  } catch {
    armCooldown();
    return null;
  }
}

/** ingreed_search가 돌려주는 항목 하나(spec §2 실측). */
export interface IngreedSearchItem {
  report_no: string;
  name: string;
  maker: string;
  category: string;
  sub: string;
  score: number;
  grade: string;
  ratable: boolean;
  mode: string;
  hidden: boolean;
}

/** 이름으로 기성식품을 검색한다. 실패하면 null(에러 아님). */
export async function searchProducts(
  q: string,
  limit: number,
  fetchFn: FetchFn = fetch,
): Promise<IngreedSearchItem[] | null> {
  return callRpc<IngreedSearchItem[]>("ingreed_search", { q, lim: limit, off: 0 }, fetchFn);
}

/** ingreed_detail 원본 응답. product.nutrition이 jsonb(§2) — label은 null일 수 있다. */
export interface IngreedDetailResult {
  product: Record<string, unknown>;
  score?: unknown;
  sources?: unknown;
  label?: unknown;
}

/**
 * report_no로 제품 상세(영양 jsonb 포함)를 조회한다. 실패하면 null.
 * ingreed_detail은 배열로 감싸 올 수도, 객체로 올 수도 있다 — 둘 다 받아 단일 객체로 normalize한다.
 */
export async function fetchProductDetail(
  reportNo: string,
  fetchFn: FetchFn = fetch,
): Promise<IngreedDetailResult | null> {
  const raw = await callRpc<IngreedDetailResult | IngreedDetailResult[]>(
    "ingreed_detail",
    { in_report_no: reportNo },
    fetchFn,
  );
  if (raw === null) return null;
  return Array.isArray(raw) ? (raw[0] ?? null) : raw;
}
