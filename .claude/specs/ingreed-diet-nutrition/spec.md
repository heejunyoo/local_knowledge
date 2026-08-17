# ingreed 제품 영양 연동 — 1단계 근거 문서

작성: 2026-08-17 · Opus 5 · 브랜치 `refactor/web-p0`

> 이 문서는 **조사 결과**다. 하위 모델은 이 리포를 모르므로, 여기 없는 것은
> 지어내지 말고 물어야 한다. 계획은 `plan.json`.

## 0. 목표 (1단계 범위)

`/diet` 에서 기성식품을 이름으로 검색해 **1회 섭취량으로 환산한 영양값**과 함께
식단에 기록한다. `diet_meal` 에 당·나트륨·포화지방까지 남는다.

**범위 밖:** 하루 건강 점수·등급 산출(2단계). 바코드 스캔(데이터가 없다, §5).

## 1. 검증 명령 — 실제로 돌려 확인한 것만

| 명령 | 결과 (2026-08-17 실측) |
|---|---|
| `cd web && npm run test` | ✅ **Test Files 21 passed · Tests 186 passed** · 488ms |
| `cd web && npx next build` | ✅ 성공. 라우트 목록 출력(`○ /diet` 포함) |
| `cd web && npm run test:regression` | ❌ **돌릴 수 없다** — §6 참조. 인수 검사에 쓰지 않는다 |

**인수 검사는 위 두 개만 쓴다.** 추측한 명령을 패킷에 박으면 하위 모델이 전부 실패로 판정한다.

## 2. 외부 데이터 — ingreed RPC (실측)

교차 프로젝트 호출이 **이미 동작한다**. 마이그레이션·데이터 복제 없음.

```
POST https://pzatcwqxlwiearxcsyxm.supabase.co/rest/v1/rpc/ingreed_search
POST https://pzatcwqxlwiearxcsyxm.supabase.co/rest/v1/rpc/ingreed_detail
헤더: apikey / Authorization: Bearer  (anon key — 설계상 공개값, RLS 가 read-only select 만 연다)
```

실측 지연: `ingreed_search` cold **2.97s** / warm **0.14~0.48s**, `ingreed_detail` **0.32s**.

`ingreed_search` 인자 `{q, lim, off, in_category, only_ratable, ...}` → 배열:

```json
{"report_no":"20030473071214","name":"...","maker":"...","category":"탄산음료",
 "sub":"탄산음료","score":100,"grade":"A","ratable":true,"mode":"A","hidden":false}
```

`ingreed_detail` 인자 `{in_report_no}` → `{product, score, sources, label}`.
`product.nutrition` 은 jsonb 이고 **실측 페이로드**는 이 모양이다:

```json
{"basis":"100mL","basisAmount":100,"servingSize":"200ml","foodWeight":"350ml",
 "energyKcal":0,"proteinG":0,"sugarG":0,"satFatG":0,"sodiumMg":0,
 "carbG":0,"fatG":0,"transFatG":0,"cholesterolMg":0}
```

- `basis` 는 `'100g' | '100mL'`, `basisAmount` 는 실측 **100 고정**
- `label` 은 **null 일 수 있다**(위 제품이 그랬다). 없다고 에러 처리하지 않는다
- 영양 필드는 **없을 수 있다**. 없는 값을 0 으로 채우면 기록이 거짓말을 한다 → `null` 로 둔다

## 3. 이식 대상 — 1회 섭취량 파서

원본: `~/ingreed/scripts/hieng_rules.ts`
회귀 테스트 원본: `~/ingreed/packages/scoring/test/serving.test.ts`

가져올 것 — `grams`(267行, private) · `declaredServingG`(191行) · `isServingTable`(202行) · `CUP_NOODLE`(170行).

**이 파서가 존재하는 이유는 조용히 틀린 값 두 개다. 둘 다 예외를 던지지 않고 그럴듯한 숫자를 준다.**

| 함정 | 내용 |
|---|---|
| **다중 표기 표** | 유탕면 754건 중 **729건**의 `servingSize` 가 `"생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g"`. 첫 숫자를 집으면 **200(생·숙면)** 이 나온다. 유탕면 값은 같은 문자열 안에 있다 — 봉지 120 · 용기 80. 컵/봉지는 **제품명**으로 가른다(`CUP_NOODLE`) |
| **단위 없는 표기** | 즉석섭취식품 **717건**의 `"1식"` 이 **1g** 으로 읽혔다. 그래서 `grams()` 는 **단위를 필수로 요구한다** — 모르면 `null`. 이 정규식을 "관대하게" 고치면 안 된다 |

**가져오지 않을 것: `roundsUpTo30g` · `SNACK_STANDARD` · `perServing`.**
그건 어린이 기호식품 고시(HIENG) 판정용 규제 환산이다. 우리가 재는 것은
**사용자가 실제로 먹은 양**이므로 30g 올림을 적용하면 안 먹은 당·나트륨이 기록된다.

## 4. 확정된 설계 판단 (상위 모델이 정했다 — 하위는 재논의하지 않는다)

| # | 판단 | 근거 |
|---|---|---|
| D1 | 1회량 = `declaredServingG(servingSize, category, name)`. `foodWeight`(총 내용량)가 그보다 **작으면 총 내용량**을 쓴다 | 한 봉지를 다 먹는 경우가 실제로 그렇다. 규제 30g 환산은 쓰지 않는다(§3) |
| D2 | 1회량을 못 구하면 `null` 을 반환하고 **사용자가 g 을 직접 입력**한다 | 모르는 것을 1g 으로 읽어 조용히 틀리는 것보다 정직하다 |
| D3 | 사용자가 **수량 배수**(0.5·1·2…)를 곱한다. 저장값은 배수 적용 후 | 반 봉지·두 개를 못 적으면 기록이 안 맞는다 |
| D4 | ingreed URL·anon key 는 **환경변수**로 받는다(`INGREED_URL`·`INGREED_ANON_KEY`). 없으면 기능이 조용히 꺼지고 기존 경로로 폴백 | 이 리포 규약: 키를 파일에 박지 않는다. anon key 가 공개값이어도 마찬가지 |
| D5 | ingreed 호출은 **서버(RPC 핸들러)에서만** 한다 | 이 리포의 모든 데이터 접근이 `lib/rpc/handlers.ts` 를 지난다. 클라이언트 직호출은 규약 이탈 |
| D6 | 타임아웃 **4초** · 실패 시 **20초 쿨다운**(그동안 호출 스킵) | cold 실측 2.97s 위 여유. 쿨다운 값은 ingreed 가 같은 사고를 겪고 채택한 값 |
| D7 | 조회한 영양값은 **기록 시점 스냅샷**으로 `diet_meal` 에 박아 저장한다. `ingreed_report_no` 도 함께 | ingreed 룰셋이 바뀌어도 과거 식단 기록이 흔들리면 안 된다 |
| D8 | **`grade`(A~E)는 저장하지 않는다.** 검색 결과 화면에만 표시 | 경계 조항("하루 점수에 쓰지 않는다")을 컬럼을 안 만드는 것으로 강제한다 |
| D9 | ingreed 조회 실패/미매칭 시에만 기존 LLM 추정 폴백(`enrichWithLlm`). 에러 경로가 아니다 | G6-3(전면 실패 시 extractive)과 같은 원칙 |

## 5. 하면 안 되는 것 (경계)

- **바코드 스캔 기능을 만들지 않는다.** 바코드 보유율 0.4%, 매핑 API(C005)는 2018 스냅샷·미신청 (`~/ingreed/docs/impl/01-data.md:29,64`). 이름 검색만 가능하다
- **영양값을 LLM 으로 만들지 않는다.** 기성품은 정답이 존재하는 영역이다
- **ingreed 리포를 수정하지 않는다.** 읽기만 한다
- **`lib/domain/diet-read.ts`(1111行)의 기존 계산을 고치지 않는다.** 하루 채점은 2단계다
- **기존 골든/회귀 테스트 파일을 수정하지 않는다**

## 6. ⚠ 차단 사항 — Knowledge Supabase 프로젝트가 내려가 있다

```
$ dig +short gppklwzcmfuuhsefdeik.supabase.co     → (응답 없음)
$ dig +short pzatcwqxlwiearxcsyxm.supabase.co     → 172.64.149.246  (ingreed 는 정상)
$ curl .../rest/v1/  → HTTP 000 (0.0013s, DNS 해석 실패)
```

DNS 레코드 자체가 없다. 무료 티어 **7일 무활동 일시정지**로 보인다 —
마지막 활동 기록이 2026-07-31(`docs/REFACTOR_STATUS.md`)이고 오늘이 2026-08-17, **17일**이다.
`/api/cron/keepalive` 가 이걸 막기로 되어 있었는데 작동하지 않았다.

**영향:**
- `npm run test:regression` 을 돌릴 수 없다 → 인수 검사에서 뺐다
- 마이그레이션 008 을 적용할 수 없다
- **복구는 오너만 가능하다** — Supabase 대시보드에서 "Resume project" 클릭 1회
  (`docs/SUPABASE_FREE_TIER_CHECK_2026-07-27.md` 항목 1: 일시정지 후 1년 이내 복구 가능)

**그래서 계획을 이렇게 짰다:** DB 가 없어도 끝낼 수 있는 것(순수 도메인 · 마이그레이션
SQL **파일 작성**)을 Phase 1 로 몰았다. 프로젝트가 살아나면 적용과 회귀만 하면 된다.
마이그레이션 **적용은 하위 모델에 시키지 않는다** — 되돌리기 어려운 실행은 상위가 한다.

## 7. 변경 지점 · 본보기 · 규약

### 변경 지점

| 파일 | 현재 | 할 일 |
|---|---|---|
| `web/lib/domain/serving-size.ts` | 없음 | 신규 — §3 이식 |
| `web/lib/domain/ingreed-nutrition.ts` | 없음 | 신규 — nutrition jsonb + 1회량 → `Estimate` 매핑(순수) |
| `web/lib/diet/ingreed-client.ts` | 없음 | 신규 — 호출·타임아웃·쿨다운·폴백 |
| `web/supabase/migrations/008_diet_meal_nutrition.sql` | 없음 | 신규 — 컬럼 5개 |
| `web/lib/db/diet.ts:260` `insertMeal` | 415行 | 파라미터·insert 확장 |
| `web/lib/rpc/handlers.ts` | 769行 | `diet_search_product` · `diet_log_product_meal` 추가 |
| `web/lib/rpc/dispatch.ts:15-33` | 70行 | 라우트 2개 등록 |
| `web/app/diet/page.tsx` | 809行 | 제품 검색 → 담기 UI |

### 본보기

- **외부 호출 + 폴백**: `web/lib/diet/nutrition-enrich.ts` (53行). 오케스트레이터는 `lib/diet/`,
  판단 로직은 `lib/domain/`(순수)에 두고, `completeFn` 을 **주입 가능한 인자**로 받아 테스트한다.
  키 없음·실패·파싱 실패를 전부 **에러가 아니라 폴백**으로 처리하는 그 모양을 그대로 따른다
- **핸들러**: `web/lib/rpc/handlers.ts:182` `diet_estimate_nutrition`
- **DB 쓰기**: `web/lib/db/diet.ts:260` `insertMeal`
- **마이그레이션 문체**: `web/supabase/migrations/007_drop_fasting_reminder_cron.sql` —
  무엇을 왜 바꾸는지 주석으로 먼저 쓴다

### 규약

- 도메인 계층(`lib/domain/`)은 **순수**하다. DB·네트워크·프레임워크를 import 하지 않는다
- 테스트: 순수 로직은 `tests/domain/*.test.ts`(vitest). 실 DB 가 필요한 것은 `tests/regression/`
- 임포트 별칭은 `@/lib/...`
- 문구는 **해요체**. 빈 상태는 짧게("찾는 제품이 없어요")
- 화면에 설명 문구를 늘어놓지 않는다. 표와 수치가 스스로 말하게 둔다
- 커밋은 PreToolUse 훅이 가로챈다 — 검증 주장을 하려면 실행 증거가 트랜스크립트에 있어야 한다

## 8. 이번 세션에서 이미 해 본 것 (중복 금지)

| 한 것 | 결과 |
|---|---|
| `npm run test` | 21 files / 186 tests 통과 |
| `npx next build` | 성공 |
| `npm run test:regression` | 6 files 실패 / 27 tests 실패 — 전부 `fetch failed`. 코드 문제 아님(§6) |
| ingreed `ingreed_search` · `ingreed_detail` 실호출 | HTTP 200. 페이로드 §2 에 기록 |
| Knowledge Supabase DNS·REST 도달 확인 | 실패. §6 |
