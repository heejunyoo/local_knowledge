# 골든 스냅샷 정규화 규칙

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` §6.3 상세.
> 구현: `web/scripts/normalize.py` (capture 시점에 즉시 적용 — 저장된 파일은 이미 정규화된 상태).

## 채취 방법
```bash
web/scripts/capture-golden.sh --out <dir>
```
- 게이트웨이는 `Knowledge.app`(포트 8741)이 기동 중이어야 함.
- 인증 토큰: `web/.secrets-local/golden-capture.token` (gitignore 대상, 값은 절대 커밋하지 않음).
  없으면 로컬(loopback)에서 `/v1/pair/start` → `/v1/pair/complete`로 신규 발급.

## 대상 메서드 (실측 확정 — §8 표 대비 차이)

포함된 18개 읽기 메서드는 실제로 살아있는 요청을 보내 응답을 확인한 것만 포함했다:
`core.ping, core.health, core.services, assistant.today, assistant.week_review,
assistant.gaps, timeline.list, knowledge.health, corpus.status, inbox.list,
diet.day_summary, diet.dashboard, diet.week_review, diet.goals, diet.profile.get,
diet.fasting.status, diet.ping, health.sync_status`

**§8 표에 있지만 실측 결과 게이트웨이에 구현되어 있지 않은 메서드** (호출 시 `-32601 Method not found`):
- `diet.json`, `inbox.json` — 디버그 전용으로 문서에 표기되어 있으나 RPC 메서드로는 존재하지 않음 (파일명과 동명이라 혼동하기 쉬움).
- `assistant.gaps.evening` — Mobile 앱의 로컬 알림 identifier 상수와 동명일 뿐, 게이트웨이 RPC 메서드가 아님.
- `assistant.onboarding.dismissed` — Mac UI의 로컬 `@AppStorage` 키와 동명일 뿐, 게이트웨이 RPC 메서드가 아님.

**의도적으로 제외**: `knowledge.ask` / `knowledge.ask.fast` — §8에서는 R(읽기)이지만 실행 Phase는 P6(생성 경로)이고 LLM 호출이라 비결정적이다. G0-1(2회 재현성) 게이트와 상충하므로 P0 골든에서 제외하고, P6에서 별도 검증(G6-1~G6-5)한다.

## 정규화 규칙 (`web/scripts/normalize.py` 구현)

| 대상 | 처리 |
|---|---|
| ISO8601 타임스탬프 값 (`\d{4}-\d{2}-\d{2}T...Z` 패턴) | `"<TS>"` 로 치환 (키 이름 무관) |
| 알려진 시간/휘발성 키 (`ts`, `date`, `updated_at`, `created_at`, `generated_at`, `started_at`, `ends_at`, `starts_at`, `heartbeat_at`, `hours_since_last_meal`) | 값 형식과 무관하게 `"<TS>"`/`"<N>"` 치환 |
| UUID (문자열 어디에 있든) | `<UUID>` 로 치환 |
| 상대 시각 문구가 섞인 라벨 키 (`starts_at_label`, `ends_at_label`, `detail_line`, `preview_line`, `hint`, `summary`, `summary_text`, `lines`) | 문자열 내 숫자 연속을 전부 `<N>` 으로 치환 (`"오늘 오후 1:51"` → `"오늘 오후 <N>:<N>"`, `"마지막 식사 후 366.5시간"` → `"마지막 식사 후 <N>시간"`) — 초기 캡처에서 `diet.fasting.status.health_reference.lines`가 이 규칙 없이는 재캡처마다 값이 바뀌는 것을 발견해 추가함. **주의**: 키 이름 기반 블랙리스트라 향후 다른 메서드에서 동명의 `lines` 키에 시간 무관 숫자가 들어있으면 과잉 마스킹될 수 있음 — 발생 시 이 규칙을 세분화할 것 |
| 부동소수 | 소수점 2자리 반올림 |
| JSON 객체 키 순서 | 재귀적으로 알파벳순 정렬 저장 (Swift Dictionary 해시 순서 비결정성 제거) |

## 검색 골든 (`web/tests/golden/search/`)
- `queries.json`: 30개 쿼리, §6.2 6종 × 5 (순수명사/조사결합형/영문기술어/한영혼합/다어절구/0건예상).
- `results/<id>.json`: `{id, category, q, count, doc_ids}` — `doc_id` 는 API가 반환한 순위 그대로(랭킹 알고리즘 회귀 대상이므로 정렬하지 않음).
- 실측 확인: `결제`(20건) vs `결제를`(3건) — 조사 결합형 과매칭 현상이 현재 FTS5로도 재현됨 (방향성 §5.1, D-4 논거).

## G0-1 재현성 검증 결과 (2026-07-27)
```
bash web/scripts/capture-golden.sh --out /tmp/g1
bash web/scripts/capture-golden.sh --out /tmp/g2
diff -r /tmp/g1 /tmp/g2   # → 출력 없음, exit=0
```
→ **PASS.** 정규화 후 완전 재현됨.

## 재채취가 필요한 경우
- P0-8 쓰기 동결이 깨졌다고 판단될 때(G1-6 실패).
- 골든 대상 메서드의 응답 스키마가 바뀌었을 때(신규 필드 추가 등 — 이 경우도 원칙적으로 기능 동결 위반이므로 우선 원인 규명).
- 재채취 시 이 문서의 "G0-1 재현성 검증 결과" 절에 새 날짜로 갱신하고, 이전 결과를 지우지 말고 append.
