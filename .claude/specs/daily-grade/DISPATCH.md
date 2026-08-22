# 하루 등급 — 작업 지시서 (하위 모델용)

발행 2026-08-20 · Opus 5 · `plan.json` 에서 기계 생성 (`validate.py emit`)

> **이 문서를 처음부터 끝까지 읽지 않는다.** 배정받은 task_id 의 절 하나만 읽고 그대로 실행한다.

## 0. 모두에게 적용되는 규칙

| | |
|---|---|
| 리포 루트 | `/Users/heejunyoo/IdeaProjects/KnowledgeApp` |
| 웹 루트 | `/Users/heejunyoo/IdeaProjects/KnowledgeApp/web` — `npm` 명령은 전부 여기서 |
| 브랜치 | `main` (2026-08-20 에 refactor/web-p0 를 흡수했다) |
| 기준선 | `npm run test` → **25 files / 244 tests 통과**. 이 숫자가 줄면 회귀다 |
| 최종 검증 | `cd web && npm run test && npx next build` |

- **패킷 밖의 파일을 만들거나 고치지 않는다.** `edit_points` 에 없는 경로를 건드렸으면 되돌린다.
- **`acceptance.command` 를 직접 돌려 통과를 확인한 뒤에 끝났다고 말한다.** 자기보고로 닫지 않는다.
- **기존 테스트를 삭제하거나 skip 하지 않는다.** 실패하면 코드를 고치지 테스트를 고치지 않는다.
- **커밋하지 않는다.** 작업트리에 남기면 상위 모델이 확인하고 커밋한다.
- **마이그레이션을 적용하지 않는다.** SQL 파일 작성까지만. `supabase` MCP·CLI 로 DB 에 접속하지 않는다.
- 막히면 **추측해서 지어내지 말고** 무엇이 막혔는지 적어 반환한다. `partial` 이 틀린 완료보다 낫다.

설계 근거는 `.claude/specs/daily-grade/spec.md` 에 있다. **필요한 절만** 연다 — 통째로 읽지 않는다.

## 1. 실행 순서

웨이브 안에서만 병렬이고, 웨이브를 건너뛰지 않는다.

**웨이브 1 — 병렬 가능** — 서로 다른 파일이고, 앞의 둘은 인수검사가 grep 이라 남의 테스트 실행에 끼어들지 않는다

- `write-migration-009` (haiku) — diet_metric 에 steps·active_energy_kcal 을 추가하는 마이그레이션 파일을 작성한다 (적용하지 않는다). · 선행: 없음
- `research-shortcuts-healthkit` (sonnet) — iOS 단축어가 HealthKit 에서 내보낼 수 있는 항목을 확인해 활동 축에 쓸 필드를 정한다. · 선행: 없음
- `grade-closed-flag` (sonnet) — gradeDay 가 하루의 종료 여부를 인자로 받아, 진행 중인 날에는 등급을 매기지 않게 한다. · 선행: 없음

**웨이브 2 — 순차** — 둘 다 npm run test / next build 를 돌린다. 같은 작업트리에서 겹치면 남이 반쯤 쓴 파일을 읽고 헛돈다

- `expose-meal-limits` (sonnet) — 이미 저장되고 있는 당·나트륨·포화지방을 읽기 경로와 도메인 타입에 노출한다. · 선행: 없음
- `add-max-duration` (sonnet) — LLM 을 호출하는 라우트에 maxDuration 을 명시해 Hobby 기본 10초 제한을 넘기지 않게 한다. · 선행: 없음

**웨이브 3 — 순차** — depends_on 이 웨이브 1·2 를 요구한다

- `grade-thresholds` (sonnet) — 조사로 확인된 공식 기준과 개인 프로필로 임계값·등급컷을 확정하고 출처를 코드 주석에 남긴다. · 선행: grade-closed-flag
- `widen-health-ingest` (sonnet) — 걸음수·활동에너지를 받고 갱신까지 되도록 health.ingest 의 metric 경로를 넓힌다. · 선행: expose-meal-limits, research-shortcuts-healthkit

**웨이브 4** — 앞의 셋에 의존한다

- `wire-day-grade-rpc` (sonnet) — day.grade RPC 를 배선해 화면이 하루 등급을 받아갈 수 있게 한다. · 선행: grade-thresholds, widen-health-ingest, expose-meal-limits

**웨이브 5 — 순차** — 둘 다 next build 를 돌린다

- `tabs-to-three` (sonnet) — 탭을 오늘·돌아보기·묻기 셋으로 줄이고 나머지 화면을 그 아래로 넣는다. · 선행: wire-day-grade-rpc
- `today-screen-grade` (sonnet) — '오늘' 화면에 하루 상태를 놓되, 진행 중인 날에는 등급 대신 무엇이 비었는지를 보여준다. · 선행: wire-day-grade-rpc

---

## 2. 작업 패킷

### write-migration-009

# 작업 지시: write-migration-009   (model_hint=haiku)
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "write-migration-009",
  "kind": "implement",
  "phase": "p4-pipe",
  "model_hint": "haiku",
  "objective": "diet_metric 에 steps·active_energy_kcal 을 추가하는 마이그레이션 파일을 작성한다 (적용하지 않는다).",
  "done_when": [
    "009_diet_metric_activity.sql 이 두 컬럼을 add column 한다",
    "왜 추가하는지와 '적용 → 코드 배포' 순서가 파일 머리 주석에 있다",
    "SQL 을 실행하지 않았다"
  ],
  "acceptance": {
    "command": "for c in steps active_energy_kcal; do grep -q \"$c\" supabase/migrations/009_diet_metric_activity.sql || exit 1; done; grep -qi 'add column' supabase/migrations/009_diet_metric_activity.sql",
    "expect_exit_code": 0,
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "files_to_create": [
    "web/supabase/migrations/009_diet_metric_activity.sql"
  ],
  "edit_points": [
    {
      "path": "web/supabase/migrations/009_diet_metric_activity.sql",
      "symbol": "alter table diet_metric",
      "what": "steps integer · active_energy_kcal numeric 을 add column 한다. 기존 행이 있으므로 not null 을 걸지 않는다. RLS 는 004_rls.sql 의 테이블 단위 정책이 그대로 적용되므로 재정의하지 않는다."
    }
  ],
  "reference_impl": {
    "path": "web/supabase/migrations/008_diet_meal_nutrition.sql",
    "why": "같은 종류의 컬럼 추가 마이그레이션이다. 주석 분량과 not null·RLS 처리 방식을 그대로 따른다"
  },
  "already_tried": [
    {
      "what": "마이그레이션 번호 확인",
      "result": "008 까지 있다. 009 는 비어 있다"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "적용은 오너가 한다. 이 태스크는 파일만 만든다",
      "컬럼 추가 전에 steps 를 select 하는 코드가 배포되면 런타임 에러다 — 순서를 주석에 남겨야 한다"
    ],
    "files": [
      "web/supabase/migrations/008_diet_meal_nutrition.sql",
      "web/supabase/migrations/005_diet_metric_context.sql"
    ],
    "excluded": "코드 변경은 다른 태스크다"
  },
  "constraints": {
    "must": [
      "파일만 만든다"
    ],
    "must_not": [
      "SQL 을 실행하지 않는다",
      "supabase CLI·MCP 로 DB 에 접속하지 않는다",
      "다른 마이그레이션 파일을 수정하지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Write",
    "Bash"
  ],
  "budget": {
    "max_turns": 15
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"write-migration-009","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### research-shortcuts-healthkit

# 작업 지시: research-shortcuts-healthkit   (model_hint=sonnet)
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "research-shortcuts-healthkit",
  "kind": "investigate",
  "phase": "p4-pipe",
  "model_hint": "sonnet",
  "objective": "iOS 단축어가 HealthKit 에서 내보낼 수 있는 항목을 확인해 활동 축에 쓸 필드를 정한다.",
  "done_when": [
    "걸음수·활동에너지·안정시심박·수면단계 각각을 가능/불가능/불확실로 판정했다",
    "판정마다 근거(원문 URL 또는 확인 절차)가 있다",
    "불확실한 것은 오너가 실기기에서 확인할 절차를 한 줄로 적었다"
  ],
  "acceptance": {
    "command": "for k in 걸음수 활동에너지 안정시심박 수면단계; do grep -q \"$k\" docs/HEALTHKIT_SHORTCUTS_2026-08.md || exit 1; done; grep -q 'https://' docs/HEALTHKIT_SHORTCUTS_2026-08.md",
    "expect_exit_code": 0,
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp"
  },
  "files_to_create": [
    "docs/HEALTHKIT_SHORTCUTS_2026-08.md"
  ],
  "already_tried": [
    {
      "what": "리포에 네이티브 HealthKit 리더가 있는지 확인",
      "result": "HKQuantityTypeIdentifier 0건. iOS 단축어 → Bearer POST 가 유일한 유입 경로다 [정정 2026-08-22: 이 grep 은 빗나갔다 — 실제 코드는 HKQuantityType.quantityType(forIdentifier:) 형태이고 네이티브 리더는 Apps/KnowledgeMobile/Sources/HealthKitBridge.swift 에 있다. 다만 목적지가 맥(Tailscale)이고 Mac 앱은 쓰기 동결이라 웹 유입 경로가 단축어뿐이라는 결론은 유효하다. docs/HEALTH_INGEST_SHORTCUT.md 참고]"
    },
    {
      "what": "앞선 기준 조사 태스크",
      "result": "이 항목은 그 태스크의 objective 범위 밖이라 조사되지 않았다(HEALTH_STANDARDS_2026-08.md §5-6)"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "단축어가 HealthKit 에서 읽어 /api/health/ingest 로 POST 하는 구조다. 네이티브 앱 변경 없이 우리 스키마만 넓히면 된다"
    ],
    "files": [
      "web/lib/health-ingest.ts",
      ".claude/specs/daily-grade/spec.md"
    ],
    "excluded": "코드 변경은 이 태스크가 아니다 — 조사 문서만 만든다"
  },
  "constraints": {
    "must": [
      "검색 결과 요약이 아니라 원문을 열어 확인한다",
      "확인 못 한 것은 확인 못 했다고 적는다"
    ],
    "must_not": [
      "코드를 수정하지 않는다",
      "확인하지 않은 것을 '가능'으로 적지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Write",
    "WebFetch",
    "WebSearch",
    "Grep",
    "Bash"
  ],
  "budget": {
    "max_turns": 40
  },
  "return_schema": {
    "items": [
      {
        "name": "string",
        "verdict": "possible|impossible|uncertain",
        "evidence": "string"
      }
    ],
    "doc_path": "string"
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": true
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"research-shortcuts-healthkit","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### grade-closed-flag

# 작업 지시: grade-closed-flag   (model_hint=sonnet)
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "grade-closed-flag",
  "kind": "implement",
  "phase": "p2b-closed",
  "model_hint": "sonnet",
  "objective": "gradeDay 가 하루의 종료 여부를 인자로 받아, 진행 중인 날에는 등급을 매기지 않게 한다.",
  "done_when": [
    "gradeDay 가 세 번째 인자로 { closed: boolean } 를 받는다",
    "closed=false 면 grade 가 null 이고 ratable 이 false 다",
    "closed=false 여도 breakdown 의 축 상태와 현재 값은 채워진다",
    "closed=true 의 기존 동작과 기존 테스트가 그대로 통과한다",
    "도메인 파일 안에서 new Date() 를 부르지 않는다"
  ],
  "acceptance": {
    "command": "npm run test",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/lib/domain/day-grade.ts",
      "symbol": "gradeDay",
      "what": "시그니처를 gradeDay(input, cuts, opts: { closed: boolean }) 로 넓힌다. closed=false 면 점수 계산은 그대로 하되 반환의 grade 를 null, ratable 을 false 로 만든다. score 는 참고값으로 남긴다."
    },
    {
      "path": "web/tests/domain/day-grade.test.ts",
      "symbol": "describe('day-grade')",
      "what": "closed=false 일 때 grade 가 null·ratable 이 false 인지, 같은 입력에 closed=true 면 등급이 나오는지 대조하는 케이스를 추가한다. 기존 케이스는 closed:true 로 호출하도록 고친다."
    }
  ],
  "reference_impl": {
    "path": "web/lib/domain/day-grade.ts",
    "why": "denominator===0 일 때 이미 score/grade 를 null 로 돌려보내는 분기가 있다. 그 반환 모양을 그대로 흉내낸다"
  },
  "already_tried": [
    {
      "what": "day-grade.ts 에서 closed 처리 여부 확인",
      "result": "없다. 206행 구현에 진행 중인 하루 개념이 아예 없다"
    },
    {
      "what": "npm run test",
      "result": "25 files / 244 tests 통과 — 이 변경 전 기준선이다"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "closed 판정(Asia/Seoul 자정 경계)은 이 태스크가 아니라 RPC 핸들러의 책임이다 — 여기서는 인자를 받기만 한다",
      "pro-rate(하루 경과 비율로 목표를 깎기)는 기각됐다. 구현하지 않는다"
    ],
    "conventions": [
      "lib/domain 은 순수하다 — DB·네트워크·프레임워크·시계를 import 하지 않는다"
    ],
    "files": [
      "web/lib/domain/day-grade.ts",
      "web/tests/domain/day-grade.test.ts",
      ".claude/specs/daily-grade/spec.md"
    ],
    "excluded": "RPC 핸들러는 이 태스크 범위가 아니다"
  },
  "constraints": {
    "must": [
      "기존 244개 테스트가 계속 통과해야 한다"
    ],
    "must_not": [
      "도메인에서 new Date() 를 부르지 않는다",
      "경과 비율로 목표를 깎지 않는다",
      "ratable 규칙(behavioral gap 또는 present<2 이면 false)을 완화하지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 30
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"grade-closed-flag","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### expose-meal-limits

# 작업 지시: expose-meal-limits   (model_hint=sonnet)
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "expose-meal-limits",
  "kind": "implement",
  "phase": "p4-pipe",
  "model_hint": "sonnet",
  "objective": "이미 저장되고 있는 당·나트륨·포화지방을 읽기 경로와 도메인 타입에 노출한다.",
  "done_when": [
    "diet_meal 조회 select 가 sugar_g·sodium_mg·satfat_g 를 가져온다",
    "도메인 Meal 에 선택 필드로 올라온다",
    "기존 kcal·proteinG 집계 결과가 바뀌지 않는다"
  ],
  "acceptance": {
    "command": "npm run test",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/lib/db/diet.ts",
      "symbol": "select(\"id,ts,items,kcal,protein_g,note\")",
      "what": "두 곳(약 45행·143행)의 select 에 sugar_g,sodium_mg,satfat_g 를 추가하고, 행 매퍼(약 32행)에서 sugarG·sodiumMg·satFatG 로 옮긴다."
    },
    {
      "path": "web/lib/domain/diet-read.ts",
      "symbol": "Meal",
      "what": "sugarG·sodiumMg·satFatG 를 선택 필드(number | null)로 추가한다. 기존 계산·집계는 건드리지 않는다."
    }
  ],
  "reference_impl": {
    "path": "web/lib/db/diet.ts",
    "why": "같은 파일의 쓰기 경로(약 296-298행)가 이미 이 세 컬럼을 다룬다. 명명 규칙을 거기서 가져온다"
  },
  "already_tried": [
    {
      "what": "008_diet_meal_nutrition.sql 과 읽기 쿼리 대조",
      "result": "컬럼은 있고 쓰기도 하는데 읽기 select 가 셋을 안 가져온다 — 섭취 상한 축이 데이터를 못 본다"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "컬럼은 008 마이그레이션으로 이미 적용돼 있다. 새 마이그레이션이 필요 없다",
      "기존 행은 이 값이 null 이다 — 결측으로 다뤄야 한다"
    ],
    "conventions": [
      "DB 는 snake_case, 도메인은 camelCase. 경계는 lib/db 의 매퍼다"
    ],
    "files": [
      "web/lib/db/diet.ts",
      "web/lib/domain/diet-read.ts",
      "web/supabase/migrations/008_diet_meal_nutrition.sql"
    ],
    "excluded": "채점 로직은 이 태스크가 아니다"
  },
  "constraints": {
    "must": [
      "기존 골든·회귀 테스트가 통과해야 한다"
    ],
    "must_not": [
      "diet-read.ts 의 기존 계산 함수를 고치지 않는다",
      "새 마이그레이션을 만들지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 30
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"expose-meal-limits","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### add-max-duration

# 작업 지시: add-max-duration   (model_hint=sonnet)
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "add-max-duration",
  "kind": "implement",
  "phase": "p0-platform",
  "model_hint": "sonnet",
  "objective": "LLM 을 호출하는 라우트에 maxDuration 을 명시해 Hobby 기본 10초 제한을 넘기지 않게 한다.",
  "done_when": [
    "LLM 을 부르는 App Router 라우트마다 export const maxDuration 이 있다",
    "값이 60 이하다 — Hobby 상한이 60s 다",
    "LLM 을 부르지 않는 라우트에는 넣지 않았다"
  ],
  "acceptance": {
    "command": "npm run test && npx next build",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/app/api",
      "symbol": "export const maxDuration",
      "what": "knowledge.ask·chat.send·diet.estimate_nutrition 등 LLM 경유 요청을 처리하는 라우트 파일에 `export const maxDuration = 60;` 을 추가한다. 어느 라우트가 LLM 을 부르는지는 lib/rpc/handlers.ts 에서 역추적한다."
    }
  ],
  "already_tried": [
    {
      "what": "Vercel Hobby 함수 제한 원문 확인",
      "result": "기본 10s · 최대 60s (vercel.com/docs/limits, 2026-08-03 갱신본)"
    }
  ],
  "context": {
    "spec_ref": "docs/PLATFORM_DECISION_2026-08.md",
    "facts": [
      "Vercel Hobby 함수는 기본 10초에서 잘린다. 60초까지만 올릴 수 있다",
      "ingreed 조회는 cold 첫 질의가 3초에 근접한다 — LLM 폴백까지 겹치면 10초는 경계 위다"
    ],
    "files": [
      "web/lib/rpc/handlers.ts",
      "web/app/api"
    ],
    "excluded": "어느 라우트가 LLM 을 부르는지는 일부러 안 적었다. 코드에서 확인해야 정확하다"
  },
  "constraints": {
    "must": [
      "기존 동작을 바꾸지 않는다 — 상수 추가만 한다"
    ],
    "must_not": [
      "60 을 넘는 값을 쓰지 않는다",
      "vercel.json 을 고치지 않는다",
      "Fluid compute 설정을 건드리지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Grep",
    "Glob",
    "Bash"
  ],
  "budget": {
    "max_turns": 25
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"add-max-duration","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### grade-thresholds

# 작업 지시: grade-thresholds   (model_hint=sonnet)
# 선행 태스크가 끝났는지 먼저 확인: ['grade-closed-flag']
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "grade-thresholds",
  "kind": "implement",
  "phase": "p3-thresholds",
  "model_hint": "sonnet",
  "depends_on": [
    "grade-closed-flag"
  ],
  "objective": "조사로 확인된 공식 기준과 개인 프로필로 임계값·등급컷을 확정하고 출처를 코드 주석에 남긴다.",
  "done_when": [
    "thresholdsFor(profile) 가 GradeThresholds 를 돌려준다",
    "임계값마다 기관·연도·URL 주석이 있다",
    "프로필 의존 값과 고정 기준이 코드에서 구분된다",
    "등급 컷 A90/B75/C60/D40 이 '의미 정박값(외부 기준 없음)'이라고 주석에 밝혀져 있다",
    "원문을 못 연 항목(WHO 2023 포화지방·IOM 단백질)은 임계값에 넣지 않았다"
  ],
  "acceptance": {
    "command": "npm run test",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "files_to_create": [
    "web/lib/domain/day-grade-thresholds.ts",
    "web/tests/domain/day-grade-thresholds.test.ts"
  ],
  "edit_points": [
    {
      "path": "web/lib/domain/day-grade-thresholds.ts",
      "symbol": "DEFAULT_THRESHOLDS, thresholdsFor",
      "what": "회복=수면 7h 하한만(D-N, 상한 감점 없음). 활동=최근 7일 중강도 150분 기준(D-J). 섭취=에너지 recommendedKcal(프로필)·단백질 0.91g/kg(D-I, KDRIs)·당 100g 상한·나트륨 2000mg 상한·포화지방 총에너지 7% 미만. 등급컷은 D-O."
    }
  ],
  "reference_impl": {
    "path": "web/lib/domain/diet-read.ts",
    "why": "recommendedKcal·bmr·tdee 가 Profile 을 받아 숫자를 내는 방식을 그대로 따른다. 이 함수들을 다시 만들지 말고 호출한다"
  },
  "already_tried": [
    {
      "what": "외부 기준 원문 조사",
      "result": "docs/HEALTH_STANDARDS_2026-08.md 완료. 수면 7h+(AASM/SRS 2015)·활동 150-300분/주(WHO 2020)·나트륨 2000mg(WHO 2012)·당 100g(식약처)·포화지방 7%(KDRIs)"
    },
    {
      "what": "코드의 recommendedProteinG(체중×1.6) 근거 확인",
      "result": "일반 인구 기준(IOM 0.8·KDRIs 0.91)의 약 2배. ISSN 2017 운동인 범위에만 해당 — 등급에는 0.91 을 쓴다(D-I)"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "포화지방 7% 는 비율이라 그날 kcal 이 필요하다. kcal 이 없거나 0이면 그 하위항목만 결측으로 둔다(D-P)",
      "식단 화면의 recommendedProteinG(×1.6)는 고치지 않는다. 등급 임계값만 따로 갖는다",
      "RECOMMENDED_WEEKLY_WORKOUTS·RECOMMENDED_WORKOUT_MINUTES_PER_DAY 는 1차 근거를 못 찾았다 — 임계값으로 쓰지 않는다"
    ],
    "conventions": [
      "lib/domain 은 순수하다",
      "임포트 별칭은 @/lib/..."
    ],
    "files": [
      "docs/HEALTH_STANDARDS_2026-08.md",
      ".claude/specs/daily-grade/spec.md",
      "web/lib/domain/day-grade.ts",
      "web/lib/domain/diet-read.ts"
    ],
    "excluded": "RPC 배선은 다음 Phase 다"
  },
  "constraints": {
    "must": [
      "원문 확인된 값만 임계값에 넣는다",
      "출처 주석에 기관·연도·URL 을 남긴다"
    ],
    "must_not": [
      "lib/domain/diet-read.ts 를 수정하지 않는다",
      "본인 과거 분포로 컷을 잡지 않는다",
      "확인 못 한 값을 채워 넣지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Write",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 40
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"grade-thresholds","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### widen-health-ingest

# 작업 지시: widen-health-ingest   (model_hint=sonnet)
# 선행 태스크가 끝났는지 먼저 확인: ['expose-meal-limits', 'research-shortcuts-healthkit']
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "widen-health-ingest",
  "kind": "implement",
  "phase": "p4-pipe",
  "model_hint": "sonnet",
  "depends_on": [
    "expose-meal-limits",
    "research-shortcuts-healthkit"
  ],
  "objective": "걸음수·활동에너지를 받고 갱신까지 되도록 health.ingest 의 metric 경로를 넓힌다.",
  "done_when": [
    "metric 샘플이 steps·active_energy_kcal 을 받는다",
    "같은 client_id 로 다시 보내면 누적값이 갱신된다 (dedupe 로 버려지지 않는다)",
    "weight_kg·sleep_h 만 보내는 기존 호출의 dedupe 동작과 반환 집계가 그대로다",
    "조사에서 '불가능'으로 판정된 항목은 추가하지 않았다",
    "도메인 Metric 에 steps·activeEnergyKcal 이 선택 필드로 있다"
  ],
  "acceptance": {
    "command": "npm run test",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/lib/health-ingest.ts",
      "symbol": "IngestSample, ingestHealthSamples",
      "what": "metric 분기에 steps·active_energy_kcal 을 추가한다. '둘 다 없으면 에러' 검사에 새 필드를 포함시킨다. ⭐ 누적 필드가 들어온 샘플은 기존 dedupe(이미 있으면 deduped++ 하고 버림) 대신 upsert 로 값을 갱신한다 — 걸음수는 하루 종일 커지므로 재전송이 정상이다. weight_kg·sleep_h 만 있는 샘플의 dedupe 경로는 그대로 둔다."
    },
    {
      "path": "web/lib/domain/diet-read.ts",
      "symbol": "Metric",
      "what": "steps·activeEnergyKcal 을 선택 필드로 추가한다. 기존 계산은 건드리지 않는다."
    }
  ],
  "reference_impl": {
    "path": "web/lib/health-ingest.ts",
    "why": "syncProfileWeight 가 이미 settings 를 upsert 한다. 같은 파일의 그 호출 방식을 그대로 쓴다"
  },
  "already_tried": [
    {
      "what": "ingestHealthSamples 의 metric 분기 정독",
      "result": "client_id 가 이미 있으면 deduped++ 하고 재삽입하지 않는다. 누적값 갱신이 구조적으로 불가능하다"
    },
    {
      "what": "health-ingest 테스트 존재 확인",
      "result": "web/tests/domain/health-ingest.test.ts 가 있다 — 기존 계약을 여기서 지킨다"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "집계 규칙(D-M): sleepH 는 최신 1건, steps·activeEnergyKcal 은 최댓값 1건. 단축어가 보내는 것은 그 시점까지의 누적 스냅샷이라 합치면 중복 집계된다",
      "client_id 를 날짜 단위로 안정되게(예: steps-2026-08-20) 두는 것이 갱신의 전제다",
      "이 파일은 SUPABASE_SERVICE_ROLE_KEY 예외가 허용된 유일한 파일이다. 예외를 다른 파일로 넓히지 않는다"
    ],
    "files": [
      "web/lib/health-ingest.ts",
      "web/tests/domain/health-ingest.test.ts",
      "docs/HEALTHKIT_SHORTCUTS_2026-08.md",
      ".claude/specs/daily-grade/spec.md"
    ],
    "excluded": "DB 컬럼 추가는 write-migration-009 가 한다. 이 태스크는 컬럼이 있다고 가정하고 코드만 쓴다"
  },
  "constraints": {
    "must": [
      "기존 weight_kg·sleep_h 경로의 idempotent 계약을 유지한다"
    ],
    "must_not": [
      "service role 예외를 다른 파일로 넓히지 않는다",
      "마이그레이션을 적용하지 않는다",
      "기존 테스트 파일을 삭제하거나 skip 하지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 40
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"widen-health-ingest","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### wire-day-grade-rpc

# 작업 지시: wire-day-grade-rpc   (model_hint=sonnet)
# 선행 태스크가 끝났는지 먼저 확인: ['grade-thresholds', 'widen-health-ingest', 'expose-meal-limits']
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "wire-day-grade-rpc",
  "kind": "implement",
  "phase": "p4-pipe",
  "model_hint": "sonnet",
  "depends_on": [
    "grade-thresholds",
    "widen-health-ingest",
    "expose-meal-limits"
  ],
  "objective": "day.grade RPC 를 배선해 화면이 하루 등급을 받아갈 수 있게 한다.",
  "done_when": [
    "day.grade 가 오늘 또는 지정한 날짜의 등급을 돌려준다",
    "오늘 요청이면 closed=false 로 호출되어 grade 가 null 이다",
    "활동 축이 최근 7일 창으로 계산된다",
    "등급을 저장하지 않고 매번 계산한다",
    "dispatch 에 등록된다",
    "next build 가 통과한다"
  ],
  "acceptance": {
    "command": "npm run test && npx next build",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/lib/rpc/handlers.ts",
      "symbol": "day_grade",
      "what": "DaySnapshot 과 Profile 을 읽어 thresholdsFor(profile) → gradeDay(input, cuts, { closed }) 를 부른다. closed 는 요청 날짜가 Asia/Seoul 기준 오늘인지로 판정한다(오늘이면 false). 활동 축 입력은 최근 7일 스냅샷의 운동 분 합계로 만든다(D-J). 프로필이 불완전하면(profileIsComplete=false) 프로필 의존 축을 결측 처리한다."
    },
    {
      "path": "web/lib/rpc/dispatch.ts",
      "symbol": "REGISTRY",
      "what": "\"day.grade\": h.day_grade 를 REGISTRY 객체에 추가한다. (심볼 이름은 HANDLERS 가 아니라 REGISTRY 다 — 73행 파일)"
    }
  ],
  "reference_impl": {
    "path": "web/lib/rpc/handlers.ts",
    "why": "assistant_today 가 DaySnapshot 과 Profile 을 읽어 조립하는 방식이 이 핸들러가 필요한 것과 같다"
  },
  "already_tried": [
    {
      "what": "dispatch.ts 심볼 확인",
      "result": "REGISTRY 다. 앞선 계획에 HANDLERS 로 잘못 적혀 있었다"
    },
    {
      "what": "day-grade.ts 반환 모양 확인",
      "result": "score·grade·ratable·confidence·breakdown·reasons·rulesetVersion"
    }
  ],
  "context": {
    "spec_ref": ".claude/specs/daily-grade/spec.md",
    "facts": [
      "등급을 저장하지 않는다(D-F). RULESET_VERSION 을 응답에 실어 화면이 표시한다",
      "closed 판정은 도메인이 아니라 이 핸들러의 책임이다(D-K)",
      "009 마이그레이션이 적용되기 전에는 steps 컬럼이 없다 — 활동 하위항목은 결측으로 흘러야 하고 select 가 깨지면 안 된다"
    ],
    "conventions": [
      "RPC 핸들러는 문자열 키로 REGISTRY 에 등록한다",
      "응답은 snake_case dict 다 — daySummaryDict 를 보라"
    ],
    "files": [
      "web/lib/rpc/handlers.ts",
      "web/lib/rpc/dispatch.ts",
      "web/lib/domain/day-grade.ts",
      "web/lib/domain/day-grade-thresholds.ts"
    ],
    "excluded": "화면은 다음 Phase 다"
  },
  "constraints": {
    "must": [
      "등급을 매번 계산한다",
      "시각 판정은 Asia/Seoul 로 한다"
    ],
    "must_not": [
      "등급을 DB 에 저장하지 않는다",
      "diet_meal 에 grade 컬럼을 만들지 않는다",
      "도메인 파일에 시계를 들여놓지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 45
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"wire-day-grade-rpc","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### tabs-to-three

# 작업 지시: tabs-to-three   (model_hint=sonnet)
# 선행 태스크가 끝났는지 먼저 확인: ['wire-day-grade-rpc']
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "tabs-to-three",
  "kind": "implement",
  "phase": "p5-ia",
  "model_hint": "sonnet",
  "depends_on": [
    "wire-day-grade-rpc"
  ],
  "objective": "탭을 오늘·돌아보기·묻기 셋으로 줄이고 나머지 화면을 그 아래로 넣는다.",
  "done_when": [
    "탭이 셋이다 — 오늘(/) · 돌아보기(/review) · 묻기(/ask)",
    "기존 /diet · /inbox · /search · /chat 라우트가 살아 있고 새 구조에서 도달 가능하다",
    "설정이 탭에서 빠지고 다른 경로로 도달 가능하다",
    "next build 가 통과한다"
  ],
  "acceptance": {
    "command": "npm run test && npx next build",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/components/BottomNav.tsx",
      "symbol": "TABS",
      "what": "6개를 3개로 줄인다. 홈→오늘, 신규 돌아보기, 채팅+검색→묻기. 설정은 탭에서 제거한다."
    },
    {
      "path": "web/app/review/page.tsx",
      "symbol": "ReviewPage",
      "what": "신규 — 과거의 날들·추세. assistant.week_review 를 재사용해 얇게 시작한다. ratable=false 인 날은 추세에서 뺀다."
    },
    {
      "path": "web/app/ask/page.tsx",
      "symbol": "AskPage",
      "what": "신규 — 묻기. 기존 /chat 과 /search 로 가는 두 갈래를 한 화면에서 고르게 한다. 기능을 재구현하지 않는다."
    }
  ],
  "reference_impl": {
    "path": "web/components/BottomNav.tsx",
    "why": "TABS 상수 배열과 active 판정 방식이 이미 있다. 구조를 그대로 두고 항목만 바꾼다"
  },
  "already_tried": [
    {
      "what": "현 탭 구성 확인",
      "result": "홈·채팅·검색·식단·인박스·설정 6개. BottomNav.tsx 39행"
    }
  ],
  "context": {
    "spec_ref": "docs/DAILY_GRADE_AND_IA_2026-08.md",
    "facts": [
      "기존 자유입력 경로는 남긴다 — ingreed 가 못 찾는 음식이 여전히 있다",
      "탐색 단위가 '도구'에서 '하루'로 바뀌는 것이 이 변경의 목적이다"
    ],
    "conventions": [
      "문구는 해요체",
      "CSS 는 기존 토큰만 쓴다"
    ],
    "files": [
      "web/components/BottomNav.tsx",
      "web/app",
      "docs/DAILY_GRADE_AND_IA_2026-08.md"
    ],
    "excluded": "등급 표시는 today-screen-grade 가 한다"
  },
  "constraints": {
    "must": [
      "기존 라우트를 삭제하지 않는다"
    ],
    "must_not": [
      "새 색상 값을 도입하지 않는다",
      "기존 화면 기능을 재구현하지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Write",
    "Bash",
    "Grep",
    "Glob"
  ],
  "budget": {
    "max_turns": 40
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"tabs-to-three","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

### today-screen-grade

# 작업 지시: today-screen-grade   (model_hint=sonnet)
# 선행 태스크가 끝났는지 먼저 확인: ['wire-day-grade-rpc']
# 목표(전체): 하루의 회복·활동·섭취를 재현 가능한 A~E 등급으로 매기고, 기록하지 않은 날이 좋은 날로 보이지 않게 한다. 그 앞에 플랫폼 선행조치(트렁크 복구·정지 원인 진단)를 둔다.
# 근거 문서: .claude/specs/daily-grade/spec.md  ← 필요한 부분만 읽는다

아래 패킷대로만 작업한다. 패킷 밖의 파일을 만들거나 고치지 않는다.

```json
{
  "task_id": "today-screen-grade",
  "kind": "implement",
  "phase": "p5-ia",
  "model_hint": "sonnet",
  "depends_on": [
    "wire-day-grade-rpc"
  ],
  "objective": "'오늘' 화면에 하루 상태를 놓되, 진행 중인 날에는 등급 대신 무엇이 비었는지를 보여준다.",
  "done_when": [
    "확정일에는 등급과 점수가 상단에 보인다",
    "오늘(진행 중)에는 등급 자리에 '아직 진행 중'과 비어 있는 입력이 보인다 — E 가 뜨지 않는다",
    "축별 점수와 근거 한 줄이 보인다",
    "ratable 이 false 면 그 사실이 드러난다",
    "confidence 가 낮으면 추정 표시가 뜬다",
    "next build 가 통과한다"
  ],
  "acceptance": {
    "command": "npm run test && npx next build",
    "expect_exit_code": 0,
    "expect_contains": [
      "passed"
    ],
    "cwd": "/Users/heejunyoo/IdeaProjects/KnowledgeApp/web"
  },
  "edit_points": [
    {
      "path": "web/app/page.tsx",
      "symbol": "HubPage",
      "what": "assistant_today 위에 day.grade 결과를 얹는다. grade 가 null 이면(진행 중) 등급 대신 미기록 항목을 보여준다 — missingLogChecklist 결과를 쓴다. 기존 브리핑 카드는 아래로 내린다."
    },
    {
      "path": "web/app/page.module.css",
      "symbol": "등급 관련 클래스",
      "what": "기존 토큰만 쓴다. 새 색상 값을 도입하지 않는다."
    }
  ],
  "reference_impl": {
    "path": "web/app/page.tsx",
    "why": "assistant_today 를 부르고 카드로 렌더하는 흐름이 이미 있다. 그 위에 얹는다"
  },
  "already_tried": [
    {
      "what": "missingLogChecklist 존재 확인",
      "result": "diet-read.ts 233행. now·today·yesterday 를 받아 시각 기반으로 빈 항목을 낸다 — 재구현하지 않는다"
    }
  ],
  "context": {
    "spec_ref": "docs/DAILY_GRADE_AND_IA_2026-08.md",
    "facts": [
      "아침에 등급 E 가 뜨는 것을 막는 것이 이 화면의 핵심 요구다(§2.6)",
      "근거 문구는 사실 진술 한 줄이다 — '수면 5.2h · 권장 7h+' 처럼. 해설조를 붙이지 않는다"
    ],
    "conventions": [
      "문구는 해요체",
      "화면에 설명을 늘어놓지 않는다"
    ],
    "files": [
      "web/app/page.tsx",
      "web/app/page.module.css",
      "web/lib/domain/diet-read.ts",
      "docs/DAILY_GRADE_AND_IA_2026-08.md"
    ],
    "excluded": "탭 구조 변경은 tabs-to-three 가 한다"
  },
  "constraints": {
    "must": [
      "진행 중인 날에 등급을 표시하지 않는다"
    ],
    "must_not": [
      "새 색상 값을 도입하지 않는다",
      "등급을 클라이언트에서 다시 계산하지 않는다",
      "'~해 보세요' 류 해설을 넣지 않는다"
    ]
  },
  "tools_allowed": [
    "Read",
    "Edit",
    "Bash",
    "Grep"
  ],
  "budget": {
    "max_turns": 40
  },
  "on_failure": {
    "retry": 1,
    "partial_ok": false
  }
}
```

반드시 아래 JSON 하나만 출력한다(설명 금지). done_when_check 는 위 done_when 과 1:1 개수로 맞춘다. acceptance.command 를 실제로 실행하고 그 exit_code 와 마지막 출력을 acceptance_run 에 담는다. 지키지 못한 제약은 unmet_constraints 에 적는다 — 비어 있다고 거짓말하지 않는다.
{"task_id":"today-screen-grade","status":"complete|partial|failed","files_changed":[{"path":"","action":"modified","summary":""}],"acceptance_run":{"command":"","exit_code":0,"output_tail":""},"done_when_check":[{"condition":"","met":true,"evidence":""}],"unmet_constraints":[],"confidence":0.0,"notes_for_orchestrator":""}

---

## 3. 반환 형식

작업이 끝나면 아래를 그대로 채워 반환한다. 스키마는 `~/.claude/skills/handoff/result.schema.json`.

```json
{
  "task_id": "<배정받은 값 그대로>",
  "status": "complete | partial | failed",
  "acceptance_run": {
    "command": "<실제로 돌린 명령>",
    "exit_code": 0,
    "output_tail": "<마지막 몇 줄>"
  },
  "files_changed": [
    "<경로>"
  ],
  "unmet_constraints": [],
  "notes": "<막힌 것·판단한 것. 없으면 빈 문자열>"
}
```