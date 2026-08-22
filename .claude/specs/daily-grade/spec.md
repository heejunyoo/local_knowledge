# 하루 등급 — 구현 근거 문서

작성 2026-08-20 · Opus 5 · 브랜치 `refactor/web-p0` · **2판(2026-08-20, 코드 대조 리뷰 반영)**
**설계 결정 원본: `docs/DAILY_GRADE_AND_IA_2026-08.md` 2판 — 먼저 읽는다.**
플랫폼(리포·호스팅) 전제는 `docs/PLATFORM_DECISION_2026-08.md`.
이 문서는 그것을 **코드로 옮기기 위한 근거**만 담는다.

## 1. 검증 명령 — 실제로 돌려 확인했다 (2026-08-20)

| 명령 | 결과 |
|---|---|
| `cd web && npm run test` | ✅ **24 files / 224 tests** · 527ms |
| `cd web && npx next build` | ✅ `Compiled successfully` |
| `cd web && npm run test:regression` | ❌ **못 돌린다** — Supabase 일시정지. 인수 검사에 쓰지 않는다 |

**일시정지는 keepalive 결함이다.** `web/vercel.json` 의 하루 1회 cron 이 실제 DB 쿼리가 아니라
정지를 못 막았다 — `docs/PLATFORM_DECISION_2026-08.md` D-5. **이 리포 전체의 선행 조치**이지
하루 등급 태스크가 고칠 것이 아니다.

## 2. 지금 있는 것 (실측)

| | 실태 |
|---|---|
| 하루 등급 | **코드 0줄.** `weekReview`는 합계, `dayBarFrom`은 카운트 |
| `DaySnapshot` | `date · meals · workouts · metrics · kcal · proteinG · workoutMinutes · summaryText`. **수면은 최상위에 없다** — `metrics[].sleepH` 안에 있다 |
| 권장치 함수 (`lib/domain/diet-read.ts`) | `bmr`(Mifflin–St Jeor) · `tdee` · `recommendedKcal` · `recommendedProteinG`(체중×1.6) · `recommendedWeeklyWorkouts` · `recommendedWorkoutMinutesPerDay` |
| `Profile` | `heightCm · weightKg · age · sex · targetWeightKg · activity` |
| `/api/health/ingest` 수용 필드 | `workout(kind, minutes)` · `metric(weight_kg, sleep_h)` **뿐** |
| 유입 경로 | iOS 단축어 → `Authorization: Bearer INGEST_API_TOKEN` → POST. 네이티브 HealthKit 리더는 리포에 없다 |
| 탭 | 홈 · 채팅 · 검색 · 식단 · 인박스 · 설정 (6개). `components/BottomNav.tsx` 39행 |

⚠ `recommendedProteinG`(체중×1.6)·`RECOMMENDED_WEEKLY_WORKOUTS`·`RECOMMENDED_WORKOUT_MINUTES_PER_DAY`
는 **출처가 코드에 없다.** → 조사 완료, 결과는 §6. 충돌 처리는 D-K.

**⚠ `/api/health/ingest` 는 갱신 경로가 없다.** `ingestHealthSamples` 는 `client_id` 로 이미 있는
행을 찾으면 `deduped++` 하고 **재삽입하지 않는다**(`lib/health-ingest.ts` metric 분기). 체중·수면처럼
하루 한 번 찍는 값에는 맞지만 **걸음수·활동에너지는 하루 종일 커지는 누적값**이라 이 구조로는
갱신이 불가능하다 — D-L 이 다룬다.

## 3. 확정된 설계 판단 (상위 모델이 정했다 — 하위는 재논의하지 않는다)

### D-A ⭐ 축 상태는 3종이다 — 이 구현의 중심

```
present            데이터 있음            → 채점한다
absent_structural  자동 축인데 데이터 없음  → 분모에서 뺀다 (재정규화)
absent_behavioral  수동 축인데 입력 없음    → 0점, 분모에 남긴다 + ratable:false
```

| 축 | 공급 | 결측이면 |
|---|---|---|
| 회복(수면) | 자동 | `absent_structural` |
| 활동(운동·걸음) | 자동 | `absent_structural` |
| 섭취(식사) | **수동** | `absent_behavioral` |

**행동적 결측을 분모에서 빼면 "기록 안 할수록 등급이 오른다".** 0점으로 분모에
남기는 것이 그걸 막는 장치다. 이 규칙을 완화하면 제품이 자기기만 기계가 된다.

### D-B 축 가중치는 **동일**(1/3씩)로 시작한다

어느 축이 더 중요한지 댈 수 있는 외부 근거가 없다. 근거 없는 가중치는 숫자로 위장한
직관이다. 근거가 생기면 그때 바꾸고, 바꾼 이유를 남긴다.

### D-C 축 내부 점수의 **형태**는 축마다 다르다 (0~100)

| 축 | 형태 | 이유 |
|---|---|---|
| 회복 | **범위형** — 권장 범위 안이면 100, 벗어난 만큼 감점 | 너무 적게 자도, 너무 많이 자도 좋지 않다 |
| 활동 | **달성률형** — 권장 대비 비율, 100 상한 | 많이 움직여서 나쁠 것이 없다(상한만 둔다) |
| 섭취 | **혼합형** — 에너지·단백질은 목표 대비, 당·나트륨·포화지방은 **상한 초과 시 감점** | 채워야 하는 것과 넘지 말아야 하는 것이 섞여 있다 |

임계값의 **실제 수치는 §6 조사 결과로 채운다.** 지금 지어내지 않는다.

### D-D 등급 컷은 **의미로 정박**한다

점수가 "권장치 대비 달성도"이므로 컷도 그 의미로 잡는다 — A는 모든 축이 권장을
충족한 날, E는 대부분 미달한 날. 정확한 경계값은 §6 조사 뒤 확정한다.
**본인 과거 분포로 컷을 잡지 않는다**(나쁜 습관이 기준선이 된다).

### D-E `confidence` = 채점에 실제로 쓰인 축의 비중

행동적 결측은 confidence 를 더 깎는다 — 값이 0점인 것과 값을 모르는 것은 다르다.

### D-F 등급을 **저장하지 않는다**. 매번 계산한다

ingreed 는 룰셋 버전별로 점수를 보존했다. 이의제기에 답해야 하기 때문이다.
**하루 등급은 사용자가 1명이고 이의제기자가 없다.** 저장 대신 규칙에
`RULESET_VERSION` 을 두고 화면에 표시한다. 규칙이 바뀌면 과거도 새 규칙으로 보인다 —
1인 앱에서는 그게 오히려 일관된다.

### D-G 활동 축은 **운동 분만으로 시작**한다

걸음수·활동에너지는 스키마 확장(Phase 4)과 수집이 끝난 뒤 하위 항목으로 붙인다.
그 전까지는 없는 값이므로 하위 항목 단위로 `absent_structural` 이다 —
축 전체가 죽지 않는다.

### D-H 노트·지식은 등급에 들어가지 않는다 (오너 승인 2026-08-20)

자동 분류는 LLM 이 한다. 분류가 바뀌면 **과거 등급이 바뀐다** — 재현성이 깨진다.
등급 옆 맥락으로만 붙인다. 나중에 넣는다면 **사용자가 직접 선언하는 이진 플래그**만
축으로 승격할 수 있다.

### D-I 단백질 충족 기준은 **KDRIs 0.91 g/kg** 이다 — 코드의 1.6 이 아니다 (2026-08-20 조사 후 확정)

조사 결과 코드의 `recommendedProteinG = 체중 × 1.6` 은 **일반 인구 기준이 아니다.**

| 기준 | 값 | 대상 |
|---|---|---|
| KDRIs 2020 권장섭취량(RNI) | **0.91 g/kg** | 일반 성인 (결핍 예방) |
| IOM/WHO DRI | 0.8 g/kg | 일반 성인 |
| ISSN Position Stand 2017 | 1.4~2.0 g/kg | **운동선수·활동적 인구** |

`1.6` 은 ISSN 범위의 정중앙값이다. 즉 **운동인 기준**이고, 일반 기준의 약 2배다.
그대로 등급 임계값으로 쓰면 평범한 날은 거의 항상 미달로 찍힌다.

**결정: 등급의 단백질 충족선은 KDRIs RNI 0.91 g/kg 을 쓴다.**
- 국내 1차 근거가 있다 (`e-jnh.org` 2022;55(1):10, 한국영양학회)
- 단백질은 **목표형(상한 100)** 이라 더 먹어도 감점이 없다 → 운동인에게 불리하지 않다
- 기존 `recommendedProteinG`(1.6)은 **식단 화면의 개인 목표로 그대로 둔다.** 등급 임계값으로만 쓰지 않는다.
  두 숫자가 다른 이유를 코드 주석에 남긴다

### D-J 활동 축은 **7일 롤링 창**으로 채점한다 (2026-08-20 조사 후 확정)

WHO 2020 신체활동 권장은 **주 150~300분(중강도)** 이다. 하루 단위 권장치가 원문에 없다.
150 ÷ 7 같은 환산은 **원문에 없는 값을 지어내는 것**이다.

**결정: 활동 축 점수 = 최근 7일 누적 중강도 분 ÷ 150 (상한 100).**
하루 화면에 보이되 기준의 단위는 원문 그대로 유지한다.

⚠ 코드의 `RECOMMENDED_WEEKLY_WORKOUTS`(활동수준별 3~5회)·`RECOMMENDED_WORKOUT_MINUTES_PER_DAY`
(20~45분)는 **조사로도 1차 근거를 찾지 못했다.** 등급 임계값으로 쓰지 않는다.

### D-K ⭐ 진행 중인 하루에는 등급을 매기지 않는다 (설계 §2.6)

`gradeDay` 는 **그날이 끝났는지**를 인자로 받는다. 날짜 판단을 도메인 함수 안에서 `new Date()` 로
하지 않는다(순수 규약 위반이고 테스트가 시계에 묶인다).

```
gradeDay(input, thresholds, { closed: boolean })

closed: true   확정일  → §D-A 그대로. grade 를 낸다
closed: false  오늘    → grade = null, ratable = false.
                        축별 present/absent 상태와 현재 값만 채운다
```

- `closed` 판정(로컬 자정 경계, Asia/Seoul)은 **호출부(RPC 핸들러)의 책임**이다.
- **pro-rate 하지 않는다.** "점심까지 하루 치의 몇 %"에 근거가 없다(설계 §2.6).
- 오늘 화면은 등급 대신 **무엇이 비었는지**를 보여준다 — `missingLogChecklist(now, today, yesterday)`
  (`diet-read.ts:233`)가 이미 시각 기반으로 그 일을 한다. 재구현하지 않는다.

### D-L ratable 게이트 — 쓰인 축이 2개 미만이면 false (설계 §2.2 2판)

`absent_behavioral` 이 하나라도 있으면 false — 여기에 조건을 **하나 더** 얹는다.
**채점에 실제로 쓰인 축(present)이 2개 미만이어도 false.**

자동 축 둘이 다 결측이면 재정규화가 섭취 하나로 A 를 만들어 준다. 재정규화 규칙은 그대로 두고
ratable 만 끈다 — 점수와 비교 가능성은 다른 장치다.

**이미 구현돼 있다** — `web/lib/domain/day-grade.ts` `ratable: !hasBehavioralGap && presentCount >= 2`.
이 절은 그 코드의 근거를 사후에 문서로 고정한 것이다(리뷰와 구현이 같은 결론에 독립적으로 도달했다).

### (단백질) → **D-I 로 통일.** 별도 결정을 두지 않는다

리뷰 단계에서 같은 취지의 결정을 중복 작성했다가 D-I 로 합쳤다. 요지는 D-I 와 같다 —
등급 임계값은 KDRIs 0.91 g/kg, 식단 화면의 `recommendedProteinG`(×1.6)는 **고치지 않는다**.

### D-M metric 집계 규칙 — 하루에 행이 여러 개다

`DaySnapshot.metrics` 는 배열이다. 기존 코드는 수면을 **마지막 값 하나**로 고른다
(`latestSleepHours` `diet-read.ts:261`, `sleepPick` `:803`). 새 필드도 규칙을 명시한다.

| 필드 | 집계 | 이유 |
|---|---|---|
| `sleepH` | **최신 1건** | 기존 동작과 같게 둔다 |
| `steps` · `activeEnergyKcal` | **최댓값 1건** | 단축어가 보내는 것은 그 시점까지의 **누적 스냅샷**이다. 합치면 중복 집계된다 |

- **수면의 날짜 귀속**: `ts` 가 속한 날에 귀속한다(기상 시각이면 오늘). 기존 `latestSleepHours` 와
  같은 기준이라 새 규칙을 만들지 않는다 — 바꾸려면 별도 결정이 필요하다.
- **갱신 경로**: 누적값이므로 재전송이 필요하다. `client_id` 를 **날짜 단위로 안정되게**
  (예: `steps-2026-08-20`) 두고 metric 분기에서 dedupe 대신 **upsert** 한다.
  기존 `weight_kg`·`sleep_h` 경로의 dedupe 동작은 **바꾸지 않는다**(idempotent 계약이 깨진다).

### D-N 회복 축은 **하한형**으로 시작한다 — 상한 감점을 넣지 않는다

D-C 는 회복을 "범위형"(너무 많이 자도 감점)으로 적었다. 그런데 조사 결과 **상한에 확정 수치가 없다** —
AASM/SRS 2015 는 7h 하한만 합의했고 9h 초과는 "건강 위험 여부 **불확실**"이라고 명시했다.

**결정: 7h 미만만 감점한다. 초과 감점은 넣지 않는다.**
§7 의 "원문 확인 없이 임계값을 넣지 않는다"가 D-C 의 형태 선언보다 우선한다.
근거가 생기면 범위형으로 되돌린다 — 그때 이 절을 고치고 이유를 남긴다.

### D-O 등급 컷 — A 90 / B 75 / C 60 / D 40

점수는 "권장 대비 달성도"다(D-D). 컷도 그 의미로 정박한다.

| 등급 | 컷 | 의미 |
|---|---|---|
| A | ≥ 90 | 모든 축이 권장을 충족했다 |
| B | ≥ 75 | 대체로 충족, 한 축이 조금 모자랐다 |
| C | ≥ 60 | 절반쯤 충족 |
| D | ≥ 40 | 대부분 미달 |
| E | < 40 | 거의 기록되지 않았거나 거의 미달 |

**본인 과거 분포로 잡지 않았다**(D-D). 이 수치는 관측이 아니라 의미 정박이므로
`day-grade-thresholds.ts` 주석에 "외부 기준 없음 — 의미 정박값"이라고 밝힌다.

### D-P 섭취 상한 3종은 **읽기 경로가 없다** — 먼저 뚫는다

`008_diet_meal_nutrition.sql` 이 `sugar_g`·`sodium_mg`·`satfat_g` 를 DB 에 넣었고 쓰기도 하는데
(`lib/db/diet.ts:296-298`), **읽기 쿼리가 이 셋을 안 가져온다**
(`lib/db/diet.ts:45,143` 의 `select("id,ts,items,kcal,protein_g,note")`, 매퍼는 `:32`).
도메인 `Meal` 타입에도 없다.

→ select 와 `Meal` 에 **선택 필드로 추가**한다. 기존 계산은 건드리지 않는다(D-L 의 `Metric` 확장과 같은 방식).
그 전까지 이 세 하위항목은 값이 없으므로 **구조적 결측**으로 다룬다.

**⚠ 008 은 아직 DB 에 적용되지 않았다** (Supabase 일시정지로 보류 — `REFACTOR_STATUS.md`).
새 마이그레이션이 필요 없다는 것은 맞지만 "이미 적용됐다"는 것은 틀렸다. 쓰기 경로가 이미 이 세
컬럼을 쓰고 있어 코드는 진작부터 008 에 의존한다 — 이 변경이 새 위험을 만든 것은 아니다.
**적용 순서는 008 → 009 → 코드 배포다.**

**포화지방은 비율 기준(총에너지 7% 미만)이라 그날 `kcal` 이 필요하다.** `kcal` 이 없거나 0이면
이 하위항목만 결측으로 둔다 — 분모를 0으로 나누지 않는다.

### D-Q 프로필 미완성은 **행동적 결측**이다 (배선 중 확정)

프로필이 없으면 섭취 목표(kcal·단백질)를 계산할 수 없다. 이때 섭취 축을 어떻게 둘지가
정해져 있지 않았다.

**결정: `absent_behavioral`.** 구조적으로 두면 구멍이 생긴다 — 프로필을 비워 두면 섭취 축이
분모에서 빠지고, 음식을 한 번도 기록하지 않아도 수면·활동만으로 A 가 나온다. §2.2 가 막으려던
바로 그 경로다.

**반론도 적어 둔다**: 프로필 미완성은 "그날의 행동"이 아니라 설정 누락이라 성격이 다르고,
잘 먹은 날도 0점이 된다. 그래도 자기기만 방지가 우선이고, 이유 문구("프로필 미완성 — 섭취
목표를 계산할 수 없음")로 원인이 드러나므로 사용자가 오해하지 않는다.

### D-R 활동 축은 결측 상태를 가질 수 없다 — 알려진 한계

운동 기록이 하나도 없으면 "안 움직인 날"과 "워치를 안 찬 날"이 구분되지 않는다. 지금 활동 축은
운동 분만 쓰므로(D-G) 데이터 부재를 감지할 신호 자체가 없다 — 그래서 **항상 `present`(0분)** 로
채점된다.

D-A 대로면 자동 축 결측은 `absent_structural` 이어야 하지만, 그렇게 하려면 "기록이 없다"와
"0분이다"를 가르는 신호가 필요하다. 걸음수가 채점에 들어오면(009 적용 + 조사 확정 후) 그 신호가
생긴다 — 그때 이 절을 다시 연다.

**부작용**: 활동이 항상 `present` 라 D-L 의 게이트(present ≥ 2)가 그만큼 쉽게 충족된다.
회복이 하나만 더 있으면 ratable 이 켜진다.

## 4. 변경 지점

| 파일 | 현재 | 할 일 |
|---|---|---|
| `web/lib/domain/day-grade.ts` | **206행 작성됨**(미커밋) | D-K(`closed`) 미반영 — 그 인자만 추가한다 |
| `web/lib/domain/day-grade-thresholds.ts` | 없음 | 신규 — §6 조사로 확정된 임계값 + 출처 주석 |
| `web/lib/domain/diet-read.ts` | 1111행 | **읽기만.** `DaySnapshot`·`Profile`·`recommended*` 를 입력으로 쓴다 |
| `web/lib/health-ingest.ts` | — | `steps` · `active_energy_kcal` 수용 |
| `web/supabase/migrations/009_*.sql` | 없음 | 신규 — `diet_metric` 확장 (**파일만**, 적용은 상위) |
| `web/lib/rpc/handlers.ts` | 800행+ | `day.grade` 핸들러 |
| `web/lib/rpc/dispatch.ts` | 73행 · 심볼은 `REGISTRY`(`HANDLERS` 아님) | 라우트 등록 |
| `web/components/BottomNav.tsx` | 39행 | 탭 6 → 3 |
| `web/app/page.tsx` | — | "오늘" — 등급이 여기 산다 |

## 5. 본보기 · 규약

- **채점 구조의 본보기**: `~/ingreed/packages/scoring/src/score.ts` — `ScoreResult`
  (`score·grade·confidence·ratable·breakdown·reasons·rulesetVersion`) 의 **모양만** 가져온다.
  값·임계값·재정규화 규칙은 가져오지 않는다(§3 D-A 가 다르다)
- **순수 도메인 규약**: `lib/domain/` 은 DB·네트워크·프레임워크를 import 하지 않는다
- **테스트**: 순수 로직은 `tests/domain/*.test.ts`(vitest). 실 DB 는 `tests/regression/`
- **근거 문구**: 사실 진술 한 줄로 쓴다 — "수면 5.2h · 권장 7~9h" 처럼 값만.
  "~해 보세요" 류의 해설조를 붙이지 않는다
- **문구는 해요체.** 화면에 설명을 늘어놓지 않는다
- 임포트 별칭 `@/lib/...`

## 6. 조사 결과 (2026-08-20 완료 — `docs/HEALTH_STANDARDS_2026-08.md`)

| 항목 | 확정 | 출처 |
|---|---|---|
| 수면 | **7h 이상**(하한만 확정). 상한 9h 는 합의문이 "불확실"로 명시 | AASM/SRS 2015 |
| 신체활동 | **중강도 150–300분/주** (KDCA 동일 준용) | WHO 2020 |
| 나트륨 | **2,000mg/일** (WHO·식약처 일치. KDRIs 2,300mg 은 성격 다름) | WHO 2012 |
| 당 | **100g/일** (절대값이라 바로 채점 가능. WHO 10% 는 비율이라 보류) | 식약처 라벨 기준치 2020 |
| 포화지방 | **총에너지 7% 미만** | KDRIs 19세 이상 |
| 단백질 | ×1.6 은 일반 기준과 불일치, ISSN 1.4–2.0 범위 내 | → D-K |

**원문을 못 연 것 — 임계값에 넣지 않는다**: WHO 2023 포화지방 · IOM 단백질 0.8g/kg ·
한국 정부 수면 권장 원문. 상세는 `HEALTH_STANDARDS_2026-08.md` §5.

## 6-b. 아직 조사가 필요한 것

1. **iOS 단축어가 HealthKit 에서 실제로 내보낼 수 있는 항목** — 걸음수·활동에너지·
   안정시심박·수면단계. 문서만으로 단정하지 말고 확인 가능한 근거를 남긴다.
   (앞 조사에서 범위 밖으로 남겨졌다 — `HEALTH_STANDARDS_2026-08.md` §5-6)

## 7. 하면 안 되는 것

- **등급을 LLM 으로 산출하지 않는다**
- **행동적 결측을 재정규화하지 않는다**(D-A)
- **원문 확인 없이 임계값을 넣지 않는다**(§6)
- **본인 과거 분포로 컷을 잡지 않는다**(D-D)
- **`lib/domain/diet-read.ts` 의 기존 계산을 고치지 않는다** — 읽기만 한다
- **기존 골든·회귀 테스트 파일을 수정하지 않는다**
- **마이그레이션을 적용하지 않는다** — 파일만 만든다. 적용은 상위 모델
- **진행 중인 하루에 등급을 붙이지 않는다**(D-I)
- **도메인 함수 안에서 `new Date()` 를 부르지 않는다** — 시계는 호출부가 주입한다
- **기존 `weight_kg`·`sleep_h` 의 dedupe 동작을 바꾸지 않는다**(D-L)
- **`diet.log_metric` 은 이제 009 에 의존한다** — `insertMetric` 의 조회까지 새 컬럼을 읽는다. 적용 순서 008 → 009 → 코드 배포를 어기면 쓰기 경로가 깨진다
- **ingreed 의 제품 등급(A~E)을 하루 등급에 더하지 않는다**

## 8. 이번 세션에서 이미 해 본 것

| 한 것 | 결과 |
|---|---|
| `npm run test` | 24 files / 224 tests 통과 |
| `npx next build` | 성공 |
| 하루 등급 코드 존재 확인 | 0건 |
| `/api/health/ingest` 수용 필드 확인 | `workout(kind,minutes)` · `metric(weight_kg, sleep_h)` |
| HealthKit 네이티브 리더 확인 | `HKQuantityTypeIdentifier` 0건 — 단축어 경유가 유일 |

> **정정(2026-08-22)**: 위 "`HKQuantityTypeIdentifier` 0건 → 네이티브 리더 없음" 판정은 **근거가 틀렸다.**
> 그 리터럴이 나오는 파일은 이 문서를 포함한 문서 4개뿐이고, 실제 코드는
> `HKQuantityType.quantityType(forIdentifier: .bodyMass)` 형태라 그 grep 에 걸리지 않는다.
> 네이티브 리더는 `Apps/KnowledgeMobile/Sources/HealthKitBridge.swift` 에 **있다**(운동·수면·체중, pull-on-open).
> 다만 그 경로의 목적지는 클라우드가 아니라 Tailscale 너머의 맥이고 Mac 앱은 쓰기 동결(P0-8)이라,
> **"웹으로 들어오는 경로는 단축어뿐"이라는 결론 자체는 유효하다.** 근거만 교체한다.
> 설정 절차는 `docs/HEALTH_INGEST_SHORTCUT.md`.

| 탭 구성 확인 | 6개 (`BottomNav.tsx`) |
