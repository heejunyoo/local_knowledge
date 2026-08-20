# 하루 등급 — 구현 근거 문서

작성 2026-08-20 · Opus 5 · 브랜치 `refactor/web-p0`
**설계 결정 원본: `docs/DAILY_GRADE_AND_IA_2026-08.md` (커밋 `9729c57`) — 먼저 읽는다.**
이 문서는 그것을 **코드로 옮기기 위한 근거**만 담는다.

## 1. 검증 명령 — 실제로 돌려 확인했다 (2026-08-20)

| 명령 | 결과 |
|---|---|
| `cd web && npm run test` | ✅ **24 files / 224 tests** · 527ms |
| `cd web && npx next build` | ✅ `Compiled successfully` |
| `cd web && npm run test:regression` | ❌ **못 돌린다** — Supabase 일시정지. 인수 검사에 쓰지 않는다 |

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
는 **출처가 코드에 없다.** §6 조사 대상에 포함한다.

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

## 4. 변경 지점

| 파일 | 현재 | 할 일 |
|---|---|---|
| `web/lib/domain/day-grade.ts` | 없음 | 신규 — 축 상태·재정규화·채점(순수) |
| `web/lib/domain/day-grade-thresholds.ts` | 없음 | 신규 — §6 조사로 확정된 임계값 + 출처 주석 |
| `web/lib/domain/diet-read.ts` | 1111행 | **읽기만.** `DaySnapshot`·`Profile`·`recommended*` 를 입력으로 쓴다 |
| `web/lib/health-ingest.ts` | — | `steps` · `active_energy_kcal` 수용 |
| `web/supabase/migrations/009_*.sql` | 없음 | 신규 — `diet_metric` 확장 (**파일만**, 적용은 상위) |
| `web/lib/rpc/handlers.ts` | 800행+ | `day.grade` 핸들러 |
| `web/lib/rpc/dispatch.ts` | 71행 | 라우트 등록 |
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

## 6. 조사가 필요한 것 (원문 확인 — 값을 지어내지 않는다)

1. **외부 공중보건 기준의 실제 수치**
   - 성인 권장 수면시간 (범위)
   - 주간 신체활동 권장량 (중강도 분)
   - 당·나트륨·포화지방 일일 상한
   - 단백질 권장 섭취량 — 코드의 `체중×1.6` 이 무엇에 근거한 값인지 포함
   기관마다 값이 다르다. **원문을 열어 확인하고 URL·기관·연도를 남긴다.**
   검색 결과 요약을 출처로 쓰지 않는다.
2. **iOS 단축어가 HealthKit 에서 실제로 내보낼 수 있는 항목** — 걸음수·활동에너지·
   안정시심박·수면단계. 문서만으로 단정하지 말고 확인 가능한 근거를 남긴다.

## 7. 하면 안 되는 것

- **등급을 LLM 으로 산출하지 않는다**
- **행동적 결측을 재정규화하지 않는다**(D-A)
- **원문 확인 없이 임계값을 넣지 않는다**(§6)
- **본인 과거 분포로 컷을 잡지 않는다**(D-D)
- **`lib/domain/diet-read.ts` 의 기존 계산을 고치지 않는다** — 읽기만 한다
- **기존 골든·회귀 테스트 파일을 수정하지 않는다**
- **마이그레이션을 적용하지 않는다** — 파일만 만든다. 적용은 상위 모델
- **ingreed 의 제품 등급(A~E)을 하루 등급에 더하지 않는다**

## 8. 이번 세션에서 이미 해 본 것

| 한 것 | 결과 |
|---|---|
| `npm run test` | 24 files / 224 tests 통과 |
| `npx next build` | 성공 |
| 하루 등급 코드 존재 확인 | 0건 |
| `/api/health/ingest` 수용 필드 확인 | `workout(kind,minutes)` · `metric(weight_kg, sleep_h)` |
| HealthKit 네이티브 리더 확인 | `HKQuantityTypeIdentifier` 0건 — 단축어 경유가 유일 |
| 탭 구성 확인 | 6개 (`BottomNav.tsx`) |
