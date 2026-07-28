# Knowledge 웹 전환 액션 플랜 (P0–P7) — Sonnet 실행 가이드

| Field | Value |
|-------|-------|
| Date | 2026-07-27 |
| Status | **Action Plan (실행 지시서) — 결정 전건 확정, 착수 가능** |
| 결정 확정 | 2026-07-27 (D-1~D-5, D-2b, 골든 동결 — §2.2·§2.3) |
| 상위 문서 | `docs/REFACTOR_DIRECTION_WEB_2026-07.md` (방향성 — 결정의 근거) |
| 실행자 | **Sonnet** (세션 분리, phase 단위) |
| 목표 | Mac 상주 서버 제거 → Vercel(Next.js) + Supabase(Postgres) + GitHub, 전 구간 무료 티어 |
| 완료 정의 | **Mac 전원을 내려도 서비스가 동작한다** |

> 이 문서는 **무엇을·어떤 순서로·무엇을 통과해야 끝인지**를 정의합니다.
> **왜 그렇게 결정했는지**는 상위 방향성 문서에 있습니다. 판단이 흔들리면 방향성 문서를 읽으세요.

---

## 0. 실행 규약 (Sonnet 필독 — 매 phase 시작 시 재확인)

### 0.1 세션 규약
1. **1 세션 = 1 Phase.** Phase가 끝나면 `/clear`. Phase 중간에 다음 Phase 작업을 미리 하지 않습니다.
2. Phase 시작 시 **이 문서의 해당 Phase 절만** 읽고, 필요하면 방향성 문서의 참조 절(§표기)을 읽습니다. 전체를 다시 읽지 마세요.
3. Phase 착수 전 **Plan 모드로 그 Phase의 세부 단계를 먼저 정렬**하고 승인받습니다 (3파일 이상 변경이므로).
4. **★ Phase 종료 시 그 절을 as-built로 갱신하고, 다음 Phase 절에 "착수 전 인지"를 추가합니다.**
   (2026-07-27 P3에서 신설) 이 문서는 명세가 아니라 체크리스트이고, 규약 2번에 따라 실행자는
   **자기 Phase 절만** 읽습니다. 그래서 어떤 절의 공백·스테일 표기는 그 절을 실행하는 사람
   눈에만 보이고, 고쳐두지 않으면 다음 사람에게 그대로 재발합니다. 갱신할 것:
   - 원문과 달라진 것(파일명·버전·API 이름) → 실제 값으로 고치고 **원문 값도 함께 남긴다**
     ("원문은 X였으나 실제는 Y") — 왜 달라졌는지가 다음 판단의 근거가 됩니다.
   - **원문에 없었는데 필요했던 단계** → 절 안에 정식 단계로 추가 (P3-0, P3-3b가 그 예)
   - 미완으로 이월한 것 → "as-built (미완 — P4x로 이월)"로 명시 (P3-4가 그 예)
   - 다음 Phase의 게이트와 충돌하는 현재 구현 → 다음 Phase 절 머리에 경고
     (P3의 리다이렉트 동작 ↔ G4a-5의 401 요구가 그 예)

### 0.2 안전 바닥 (완화 불가)
- **사전 승인 필요(Ask-Before-Act):** Supabase 프로젝트 생성·스키마 적용·Vercel 배포·GitHub 레포 생성·외부 API 키 발급·기존 데이터 삭제·기존 테스트 삭제.
- **완료 = 게이트 명령 실제 실행 통과.** 게이트를 돌리지 않고 "완료"라고 보고하지 마세요.
- **한 번에 하나의 논리적 변경.** 눈에 띄는 무관한 문제는 `docs/REFACTOR_BACKLOG.md`에 적고 넘어갑니다.
- **불확실하면 추측하지 말고 파일·DB·로그를 직접 확인.** 특히 무료 티어 정책은 절대 기억에 의존하지 말고 당일 공식 문서를 확인합니다.

### 0.3 절대 금지
| 금지 | 이유 |
|---|---|
| 인증을 "나중에" 미루고 공개 URL 배포 | URL 아는 사람 = 전체 데이터 접근 (방향성 §6.5.2). **P3 전에는 Vercel 배포를 public으로 열지 않음** |
| `decade_journey`의 쿠키 프로필 패턴 이식 | 인증이 아님. 가족용 프로필 선택기 |
| 서비스 롤 키(`SUPABASE_SERVICE_ROLE_KEY`)를 클라이언트 번들에 노출 | RLS를 통째로 우회함 |
| 리팩토링 중 신기능 추가 | **기간 전체 기능 동결.** `FORWARD_DIRECTION_RESEARCH_2026-07.md` 백로그는 P6 이후 재평가 |
| **P0-8 이후 Mac 앱으로 데이터 쓰기** | 골든 스냅샷이 무효화되어 회귀 판정 불가 (§2.3). 코드로 차단하되, 우회하지도 마세요 |
| P0-8 동결 커밋을 임의로 revert | 해제 시점은 P1-5에 정의되어 있습니다 |
| 상주 워커·로컬 파일 저장·로컬 벡터 DB 패턴 재현 | Vercel에서 전부 무너짐 (방향성 §6.5.3) |
| 비밀정보를 레포/DB/문서에 기록 | 전부 Vercel·Supabase 환경변수 |

### 0.4 보고 형식
각 Phase 종료 시 다음만 보고합니다.
```
Phase: Pn
게이트: [명령] → [실제 출력 요약] → PASS/FAIL
산출물: [파일 경로 목록]
다음 Phase 선행조건: 충족/미충족(사유)
미결/발견: (있으면 3줄 이내)
```

---

## 1. 실행 전 정정 사항 (2026-07-27 실측 — 방향성 문서 대비 차이)

> 방향성 문서 작성 이후 코드·DB·vault를 직접 측정한 결과, **플랜에 반드시 반영해야 하는 차이 8건**을 확인했습니다.
> 이 절은 방향성 문서를 부정하는 게 아니라, 실행 단계에서 깨질 전제를 미리 고정합니다.

### C-1 ★ 회귀 안전망이 실제로는 거의 없다 (가장 중요)

방향성 문서 §6·§10은 `evals/scenarios`가 "재구현의 합격선을 정의한다"고 했습니다. **실측 결과 성립하지 않습니다.**

| 시나리오 | 내용 | 7-1(미팅 폐기) 이후 |
|---|---|---|
| `S02_graph_edges.json` | 미팅 파이프 상태 전이 | **소멸** |
| `S02b_recovery.json` | recording/transcribing 크래시 복구 R1–R4 | **소멸** |
| `S06_index_no_body_sot.json` | commit_pending → committed 엣지 | **소멸** |
| `S11_no_wildcard_committed.json` | committed 와일드카드 금지 | **소멸** |
| `S12_timeout_never_success.json` | ASR/요약 타임아웃 | **소멸** |
| `S05_threshold_keys.json` | 임계값 키 24개 존재 검증 | **부분 생존** (24개 중 ASR·캡처·미팅 키 19개가 무의미해짐) |

→ **결론: 리라이트를 지켜줄 기존 테스트는 사실상 0에 수렴합니다.**
→ **대응: P0의 최우선 산출물은 "미팅 아카이브"가 아니라 「골든 스냅샷 회귀 세트」 신규 구축입니다(§6).** 현행 Mac 앱이 살아 있는 지금이 유일한 기준선 채취 기회입니다. Mac 앱을 해체(P7)한 뒤에는 만들 수 없습니다.

### C-2 `PipelineGraph`는 "미팅과 무관하게 유지"할 수 없다

방향성 §7-1은 "PipelineGraph default-deny + R1–R6은 미팅과 무관하게 유지"라고 했으나, 실측한 `PipelineGraph.swift`(161줄)의 상태는 **전부 미팅 상태**입니다: `recording / recorded / transcribing / transcribed / summarizing / summarized_candidate / critic_running / review_needed / commit_pending / committed / *_failed / abandoned`.

→ 미팅을 폐기하면 **적용 대상 상태기계 자체가 사라집니다.**
→ **대응: 유지하는 것은 코드가 아니라 「패턴」입니다.** P4에서 다음 두 곳에만 default-deny 상태기계를 적용하고, 원본은 아카이브합니다.
   - `inbox_item.status`: `open → promoting → promoted | promote_failed` (와일드카드 → promoted 금지)
   - `ingest_job.status`: `queued → running → done | failed`, 그리고 R2/R3 유사 복구 규칙(고아 running 회수)
→ 이건 **결정 D-3**으로 P4 시작 시 오너 확인이 필요합니다.

### C-3 순수 도메인 로직 규모가 문서 추정(약 800 LOC)보다 크다

| 파일 | LOC | 비고 |
|---|---|---|
| `DietStore.swift` | **1,392** | 방향성 §6 표에서 누락. diet.* 메서드 24개의 실제 구현체 |
| `DietProfile.swift` | 258 | BMR/TDEE |
| `DietNutritionCalc.swift` | 257 | |
| `Thresholds.swift` | 148 | |
| `TextChunker.swift` | 156 | |
| `DietPresets.swift` | 71 | |
| `PipelineGraph.swift` + `CrashRecovery.swift` | 269 | C-2 처리 |
| **TS 번역 실질 대상** | **약 2,280 LOC** | 문서 추정의 약 2.8배 |

→ **대응: P4를 P4a(읽기 경로) / P4b(diet 쓰기 경로)로 분할**합니다(§5.5). Diet가 단일 최대 덩어리입니다.

### C-4 vault 루트가 2개이고, 인덱스에 stale 항목이 있다

```
iCloud  .../heejun_pkm/heejun_PKM        md 225개, 총 6.8MB   ← 실질 vault
~/Obsidian/Main                          Meetings/ 하위 md 3개 뿐
connected_source 4행 중 obsidian 2행이 위 두 루트를 각각 가리킴
knowledge_unit(obsidian) 224 = vault 217 + Meetings/ 7
```
→ `Meetings/` 인덱스 7건 중 **파일이 실존하는 것은 3건** → 4건 stale.
→ vault md 225 vs 인덱스 unit 217 → **불일치 8건** 존재.
→ **대응: P0 인벤토리에서 이 차이를 전수 대사하고 확정 수치를 동결**합니다. P1 마이그레이션 게이트가 이 수치를 기준으로 삼습니다.

### C-5 비밀정보가 실존한다 (스캔은 선택이 아님)

```
~/Knowledge/config/secrets.json                    (0600, 81B — LLM 키)
~/Knowledge/config/mobile_devices.json             (0600, 2.4KB — 페어링 토큰 스토어)
iCloud vault/CyberSourceKey_20250918223005.pem     ← Git 레포 이전 시 그대로 올라감
iCloud vault/postmanv2.html                        ← 내용 확인 필요
```
→ **P2에서 vault를 Git에 올리기 전 P0에서 반드시 격리.** `.pem`은 레포 밖으로 옮기고 vault에는 참조만 남깁니다.

### C-6 `fts_docs`는 unit 단위(243행), chunk 단위가 아니다

`fts_docs` 243행 = `knowledge_unit` 243행과 1:1. `knowledge_chunk` 621행은 FTS에 들어가 있지 않고 RAG 검색(`LocalRetrieve`) 전용입니다.
→ Postgres 이식 시 **검색 인덱스 단위는 unit 유지**. chunk를 FTS에 넣는 것은 변경이지 이식이 아니므로 금지(스코프 폭발).

### C-7 `chunk_vector` 621행은 마이그레이션 대상이 아니다

`LocalHashEmbedder`(69줄) 산출물 = 해시 기반 = 비의미적. 방향성 §3-B대로 벡터는 초기 비활성.
→ **이관하지 않습니다.** 스키마에 `pgvector` 컬럼만 비워두고, 재활성 시 Gemini `text-embedding-004`로 **재생성**합니다(방향성 §6.5.4 P-4).

### C-8 API 메서드 실측 = 62개, 유지 대상 = 47개

미팅·리뷰·페어링 계열 15개(`meeting.*` 13, `knowledge.review.*` 3, `knowledge.meetings`, `knowledge.systemaudio.write` 등)를 제외한 **47개**가 이식 대상입니다. 전체 매핑은 §8.

---

## 2. 확정 사항 (**미결 0건 — 전건 결정 완료**)

### 2.1 방향성 문서 확정분 (오너 승인 완료 — 재논의 금지)
| # | 결정 |
|---|---|
| F-1 | 미팅 녹음 파이프라인 **전면 폐기** (방향성 §7-1) |
| F-2 | Vault SoT = **Git 프라이빗 레포** + Obsidian Git 동기 (§7-2) |
| F-3 | DB = **Supabase (Postgres)** (§7-3) |
| F-4 | 프론트 = **Next.js App Router + TypeScript on Vercel** |
| F-5 | 프라이버시 포지션 = "내 계정 · 단일 테넌트 · redaction preflight 유지"로 하향 표기 (§7-4) |
| F-6 | 리팩토링 기간 = **기능 동결** |

### 2.2 확정 (2026-07-27 스코어링 후 오너 결정 완료 — **미결 없음**)

> 아래 6건은 결정이 끝났습니다. **Phase 실행 중 재논의하지 마세요.**
> 스코어링 기준: 실행 리스크 감소 30% · 되돌리기 용이성 20% · 무료 티어 적합 20% · 작업량 15% · 장기 유지보수 15%

| # | 결정 항목 | **확정** | 점수 | 탈락안 | 반영 위치 |
|---|---|---|---|---|---|
| **D-1** | 코드 레포 구조 | **모노레포 — 기존 `KnowledgeApp` 레포 안 `web/`, Vercel Root Directory=`web`** | 8.70 | 신규 레포 분리 (7.25) — P0 산출물·정책 문서가 다른 레포에 있어 cross-repo 참조 발생 | §3, P0-1 |
| **D-2** | vault Git 레포 | **분리 (`knowledge-vault` 프라이빗)** | — | Obsidian Git 플러그인이 *vault 루트 = git 루트*를 전제 → 기술적으로 강제. 트레이드오프 없음 | P2-1 |
| **D-2b** | DB 덤프 백업 위치 | **별도 `knowledge-backup` 프라이빗 레포** | 8.90 | vault 레포(7.40) — Obsidian이 `backups/*.sql.gz`를 vault 파일로 인식해 검색·그래프 오염 / 코드 레포(8.30) — 백업 커밋마다 Vercel 재배포 트리거 | P2-4 |
| **D-3** | `PipelineGraph` 처리 (C-2) | **패턴을 2곳에 이식**: `inbox_item` + `ingest_job`에 default-deny 상태기계 + 고아 회수 규칙 적용. 원본 Swift는 `legacy/`로 아카이브 | 8.25 | inbox 1곳만 (8.10) / 통째 아카이브 (6.90) — 승격이 Git 커밋 도중 죽으면 상태 판별 불가 | P1-2 DDL, P4a-5, P4b |
| **D-4** | 한국어 검색 게이트 | **게이트는 "현행 대비 recall 하락 0"(동등). 단 `pg_trgm` 인덱스·쿼리 경로를 함께 구축하고 `settings` 플래그로 전환 가능하게 한다.** 실제 품질 판단은 P5에서 써보고 결정 | 8.60 | 동등만 (8.40) — 낮은 현행 품질 고착 / 조사 흡수 필수 (7.65) — 임계값·랭킹 튜닝으로 P1이 1~2세션 길어짐 | P1-4, P4a-4 |
| **D-5** | Mac 앱 병행 운영 종료 | **P5 게이트 통과 + 7일** | — | 기본값 유지 | P7 선행조건 |

### 2.3 ★ 운영 결정 — 골든 스냅샷 유효성 (C-1 대응)

| 결정 | **P0 골든 채취 완료 시점부터 Mac 앱에서의 쓰기를 동결한다** (점수 8.80) |
|---|---|
| 동결 범위 | `diet.log_*`, `diet.delete_*`, `diet.goals.set`, `diet.profile.set`, `inbox.create/promote/delete`, `corpus.sync`, `search.reindex` — **조회는 자유** |
| 해제 시점 | **P1 게이트(G1-1~G1-4) 통과 직후.** 이후 기록은 웹이 아직 없으므로 메모 등에 임시 보관했다가 P4b 완료 후 입력 |
| 탈락안 | P1 직전 재채취(7.90) — 재채취 시점을 놓치면 회귀가 통째로 어긋남 / 동결 없이 진행(5.20) — 안전망 무력화 |
| 강제 수단 | P0-9에서 Mac 앱 쓰기 경로를 실제로 막습니다(단순 "조심하기"에 의존하지 않음) |

---

## 3. 타깃 디렉토리 구조 (D-1 **확정**: 모노레포)

```
~/IdeaProjects/KnowledgeApp/
├── web/                          ← 신규. Vercel Root Directory
│   ├── app/
│   │   ├── (auth)/login/
│   │   ├── (app)/                ← 인증 필요 구간
│   │   │   ├── page.tsx          Hub (assistant.today)
│   │   │   ├── search/  chat/  diet/  inbox/  settings/
│   │   └── api/
│   │       ├── rpc/route.ts      ← 기존 JSON-RPC 형태 유지(호환 계층)
│   │       ├── assistant/  diet/  inbox/  knowledge/  health/
│   ├── lib/
│   │   ├── domain/               ← Swift → TS 1:1 번역본
│   │   │   ├── diet-store.ts  diet-profile.ts  nutrition-calc.ts  presets.ts
│   │   │   ├── thresholds.ts  text-chunker.ts
│   │   │   └── state-machine.ts  ← D-3: inbox_item + ingest_job default-deny
│   │   ├── db/                   ← Supabase 클라이언트 · 쿼리
│   │   ├── llm/                  ← provider catalog · router · cache · throttle
│   │   ├── settings.ts           ← P-1 패턴 (DB Settings + 메모리 캐시)
│   │   └── redaction.ts
│   ├── supabase/migrations/      ← 001_init.sql ...
│   ├── tests/
│   │   ├── golden/               ← §6 골든 스냅샷 (P0 산출)
│   │   ├── domain/               ← 도메인 유닛 테스트
│   │   └── regression/           ← 골든 대조 러너
│   └── scripts/                  ← 마이그레이션 · 백업 스크립트
├── legacy/                       ← P7에서 Swift 전체 이동
├── docs/  Schemas/  evals/       ← 유지 (정책 SoT)
└── archive/2026-07-meeting/      ← P0에서 미팅 자산 이동
```

---

## 4. Phase 개요

| Phase | 목표 | 핵심 산출물 | 게이트 (한 줄) | 선행 |
|---|---|---|---|---|
| **P0** | 기준선 동결 | 골든 스냅샷 · 데이터 인벤토리 · 백업 · 비밀정보 격리 · **Mac 쓰기 동결** · 미팅 아카이브 | 골든 세트 100% 재현 + 쓰기 차단 실효 | — |
| **P1** | 스키마 + 데이터 이관 | Postgres DDL(+상태기계 테이블) · 마이그레이션 스크립트 · 검색 3모드 · 비교 리포트 | 행수 100% 일치 + 검색 recall 하락 0 | P0 |
| **P2** | Vault → Git | `knowledge-vault` + `knowledge-backup` 2개 레포 · Obsidian Git · pg_dump Actions | 웹↔Obsidian 양방향 편집 무충돌 왕복 | P0 |
| **P3** | 인증 | Supabase Auth + RLS + Next 미들웨어 | 미인증 요청이 **DB 레이어에서** 차단 | P1 |
| **P4a** | 읽기 API + 상태기계 | assistant/timeline/knowledge/inbox 조회 · `state-machine.ts`(D-3) | 골든 회귀 통과 + default-deny 증명 | P1 P3 |
| **P4b** | Diet API (쓰기 포함) | diet.* 24개 + 도메인 TS 번역 | diet 골든 + 유닛 테스트 통과 | P4a |
| **P5** | 웹 UI | Hub·검색·Chat·Diet·Inbox·PWA | URL만으로 폰·데스크톱 동작 | P4b |
| **P6** | 생성 경로 | LLM 캐스케이드 + 캐시 + throttle + extractive fallback | 모든 provider 실패 시에도 응답 | P5 |
| **P7** | 레거시 해체 | LaunchAgent 제거 · 4.4GB 삭제 · Swift 아카이브 | **Mac 전원 OFF 상태에서 전 기능 동작** | P6 |

---

## 5. Phase 상세

---

### P0 — 기준선 동결 (Freeze)

> **이 Phase의 성격: 코드를 한 줄도 쓰지 않습니다. 되돌릴 수 없는 것을 되돌릴 수 있게 만드는 단계입니다.**
> C-1 때문에 **P0가 전체 리팩토링의 성패를 가릅니다.** 여기서 기준선을 못 만들면 이후 모든 Phase가 "느낌으로 맞는지" 판단하게 됩니다.

#### 입력
- `~/Knowledge/` (index/, config/, services/, vault/)
- iCloud vault: `~/Library/Mobile Documents/com~apple~CloudDocs/heejun_pkm/heejun_PKM`
- 현행 Mac 앱 (게이트웨이 `/v1/rpc` 응답 가능 상태여야 함)

#### 작업 단계

**P0-1. 레포 위생 (D-1 확정: 모노레포)**
1. `git status` 확인 — 현재 `Apps/KnowledgeMobile/*` 등 미커밋 변경 존재. 의미 있는 변경이면 커밋, 아니면 stash. **더티 상태로 P1에 진입 금지.**
2. 작업 브랜치 생성: `refactor/web-p0`.
3. **기존 `KnowledgeApp` 레포 안에서 작업합니다.** 신규 코드 레포를 만들지 마세요(D-1). `web/` 디렉토리만 생성하고 Vercel Root Directory는 P4a에서 `web`으로 설정합니다.
4. `.gitignore`에 `web/node_modules/`, `web/.next/`, `web/.env*.local` 추가.

**P0-2. 읽기전용 백업 (되돌리기 지점)**
```bash
BK=~/Knowledge-backup-2026-07-27
mkdir -p $BK
sqlite3 ~/Knowledge/index/knowledge.db ".backup '$BK/knowledge.db'"
cp -R ~/Knowledge/services $BK/services
cp -R ~/Knowledge/config   $BK/config
ditto "$HOME/Library/Mobile Documents/com~apple~CloudDocs/heejun_pkm/heejun_PKM" $BK/vault
chmod -R a-w $BK
shasum -a 256 $BK/knowledge.db > $BK/CHECKSUMS.txt
```
- 백업은 **읽기전용으로 잠급니다.** 이후 어떤 Phase도 이 디렉토리에 쓰지 않습니다.

**P0-3. 데이터 인벤토리 동결 → `docs/DATA_INVENTORY_2026-07-27.md`**

아래 수치를 **직접 쿼리해서** 기록합니다. 문서의 숫자를 베끼지 마세요.
```bash
sqlite3 ~/Knowledge/index/knowledge.db "
select 'knowledge_unit', count(*) from knowledge_unit
union all select 'knowledge_chunk', count(*) from knowledge_chunk
union all select 'note_mirror', count(*) from note_mirror
union all select 'source_pointer', count(*) from source_pointer
union all select 'connected_source', count(*) from connected_source
union all select 'fts_docs', count(*) from fts_docs
union all select 'chunk_vector', count(*) from chunk_vector
union all select 'meeting', count(*) from meeting
union all select 'action_item', count(*) from action_item
union all select 'pipeline_events', count(*) from pipeline_events;"
```
그리고 **C-4 불일치를 전수 대사**합니다.
- vault 파일 목록(`find ... -name '*.md'`) vs `knowledge_unit.sot_ref` 를 diff.
- 결과를 표로: `인덱스에만 있음(stale) / 파일에만 있음(미인덱스) / 양쪽 일치`.
- `Meetings/` 접두 7건은 F-1에 따라 **아카이브 대상으로 분류**(마이그레이션 제외).
- **이 대사 결과가 P1의 이관 목표 행수를 정의합니다.** 예상 결과: vault_md 이관 대상 ≈ 217 − (Meetings 7) + (미인덱스 md), notes_app 19.

**P0-4. ★ 골든 스냅샷 회귀 세트 구축 → `web/tests/golden/`**

**C-1 대응. P0의 최우선 산출물입니다.** 상세 설계는 §6.
1. 현행 Mac 앱을 기동하고 `/v1/rpc`가 응답하는지 확인.
2. `scripts/capture-golden.sh` 작성 — §8 표의 **읽기 계열 메서드 전부**를 호출해 응답 JSON을 저장.
3. 검색 기준선: 대표 쿼리 30개(§6.2)를 `knowledge.search`로 실행, `doc_id` 순위 리스트를 저장.
4. 시간 의존 필드(`ts`, `generated_at`, 상대 날짜 문구)는 **정규화 규칙**을 같이 저장(§6.3). 안 하면 회귀가 매일 깨집니다.
5. **재실행 재현성 검증**: 스크립트를 2회 돌려 정규화 후 diff가 0인지 확인. 이게 P0 게이트입니다.

**P0-5. 비밀정보 격리 (C-5)**
1. vault 전수 스캔:
   ```bash
   cd "$HOME/Library/Mobile Documents/com~apple~CloudDocs/heejun_pkm/heejun_PKM"
   find . -type f ! -name '*.md' | grep -v '/\.obsidian/'
   grep -rlEi 'BEGIN (RSA |EC |OPENSSH |PRIVATE)|api[_-]?key|secret|password|token' --include='*.md' . | head -50
   ```
2. `CyberSourceKey_*.pem` → `~/Secrets/` 로 이동. vault에는 `.md` 참조 노트만 남김.
3. `postmanv2.html` 내용 확인 후 비밀정보 포함 시 동일 처리.
4. 발견 목록을 `docs/DATA_INVENTORY_2026-07-27.md`에 기록 (**값이 아니라 경로와 종류만**).
5. `~/Knowledge/config/secrets.json`의 키 이름 목록을 기록 → P4/P6의 환경변수 이름 매핑에 사용. **값은 절대 문서에 쓰지 않습니다.**

**P0-6. 미팅 자산 아카이브 (F-1) — 삭제가 아니라 이동**
- `archive/2026-07-meeting/` 로 이동: `Schemas/meeting-summary-v1.json`, `evals/scenarios/{S02,S02b,S06,S11,S12}*.json`.
- Swift 코드는 **이 시점에 건드리지 않습니다** (P7에서 일괄). 지금 지우면 P0-4 골든 채취가 불가능해집니다.
- `archive/2026-07-meeting/README.md`에 "왜 아카이브했는가 + 복원하려면 무엇이 필요한가" 5줄 기록.

**P0-7. 문서 정합화**
- `README.md`, `docs/core_platform_sketch.md`, `docs/FORWARD_DIRECTION_RESEARCH_2026-07.md`의 J2(미팅) 서술에 **"2026-07 폐기 — REFACTOR_DIRECTION_WEB_2026-07.md §7-1"** 주석 추가. 본문 재작성은 하지 않습니다(One Thing).
- `FORWARD_DIRECTION` 백로그의 F-S1·F-S2·F-S3·F-S4에 **소멸** 표기.

**P0-8. ★ Mac 앱 쓰기 동결 (§2.3 확정)**

> **실행 시점 주의: 번호는 8이지만 P0-4(골든 채취) 게이트 G0-1 통과 직후에 바로 실행하세요.**
> P0-5·6·7은 `~/Knowledge` 데이터를 쓰지 않으므로 동결 이후에 진행해도 무방합니다.

> "조심해서 안 쓰기"에 의존하지 않습니다. **실제로 막습니다.** 오너가 습관적으로 식사 1건만 기록해도 골든이 어긋납니다.

1. 게이트웨이 쓰기 경로를 차단하는 **최소 변경 1건**을 적용합니다. `MobileHTTPServer.swift`의 RPC 디스패치 진입부에 동결 가드를 추가:
   ```swift
   // REFACTOR P0: 골든 스냅샷 기준선 보호 (docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §2.3)
   // P1 게이트 통과 후 이 블록을 제거한다.
   private static let frozenWriteMethods: Set<String> = [
       "diet.log_meal", "diet.log_workout", "diet.log_metric",
       "diet.delete_meal", "diet.delete_workout", "diet.delete_metric",
       "diet.goals.set", "diet.profile.set",
       "diet.fasting.start", "diet.fasting.end",
       "inbox.create", "inbox.promote", "inbox.delete",
       "corpus.sync", "search.reindex",
       "assistant.onboarding.dismissed", "health.ingest",
   ]
   ```
   → 해당 메서드는 `-32000 / "frozen_for_migration"` 에러를 반환합니다.
2. **이것은 §0.2의 "One Thing" 예외가 아닙니다.** 별도 커밋으로 분리하고 메시지에 `chore(p0): freeze write paths for golden baseline` 로 남깁니다. **P1 게이트 통과 후 되돌릴 커밋이므로 revert 대상 SHA를 `docs/DATA_INVENTORY_2026-07-27.md`에 기록**하세요.
3. Apple Shortcuts의 `health.ingest` 자동화도 일시 중지 (오너가 직접).
4. 동결 기간 중 기록할 내용은 vault의 `10 📥 수집함/` 에 md로 임시 보관합니다. P4b 완료 후 웹에서 입력.
5. 동결 확인:
   ```bash
   curl -s -X POST http://127.0.0.1:<port>/v1/rpc -H 'Authorization: Bearer <token>' \
     -d '{"jsonrpc":"2.0","id":1,"method":"diet.log_meal","params":{"note":"freeze-test","kcal":1}}'
   # → error.message == "frozen_for_migration"
   curl -s -X POST ... -d '{"jsonrpc":"2.0","id":2,"method":"assistant.today"}'
   # → 정상 응답 (조회는 자유)
   ```

**P0-9. Supabase 무료 티어 *정책* 실측 → `docs/SUPABASE_FREE_TIER_CHECK_2026-07-27.md`**

용량이 아니라 **정책**을 확인합니다 (방향성 §5.2.3). 기억이 아니라 **당일 공식 문서 + 실제 대시보드**로 확인하고 출처 URL과 확인 일자를 남깁니다.
| 확인 항목 | 합격 조건 |
|---|---|
| 무활동 시 프로젝트 일시정지 기준일 · 복구 방법 | 기준일이 명시되고, 복구가 수동 클릭 1회 수준 |
| keep-alive 핑이 정지 회피에 유효한지 | 공식 문서 기준 "요청 발생 = 활동"으로 인정되는지 |
| `pg_cron` 무료 티어 활성 가능 | 확장 활성화 성공 |
| `pg_trgm` 활성 가능 | 확장 활성화 성공 |
| `pgvector` 활성 가능 | 확장 활성화 성공 (당장 안 써도 경로 확보) |
| 무료 티어 백업 정책 | PITR 없음 확인 → pg_dump 백업 필수임을 확정 |

- **하나라도 실패하면 P1에 진입하지 말고 오너에게 보고합니다.** 대안은 Neon(방향성 §5 표)이며, 그 경우 인증 전략(D)이 통째로 바뀌므로 오너 결정 사항입니다.

#### 산출물
- `~/Knowledge-backup-2026-07-27/` (읽기전용) + `CHECKSUMS.txt`
- `docs/DATA_INVENTORY_2026-07-27.md`
- `web/tests/golden/**` + `web/scripts/capture-golden.sh` + `web/tests/golden/NORMALIZE.md`
- `docs/SUPABASE_FREE_TIER_CHECK_2026-07-27.md`
- `archive/2026-07-meeting/**`
- `docs/REFACTOR_BACKLOG.md` (빈 파일로 생성)
- 쓰기 동결 커밋 1건 (revert 대상 SHA를 인벤토리 문서에 기록)

#### 게이트 (전부 통과해야 P1)
```bash
# G0-1 골든 재현성
bash web/scripts/capture-golden.sh --out /tmp/g1 && bash web/scripts/capture-golden.sh --out /tmp/g2
diff -r /tmp/g1 /tmp/g2   # → 출력 없음

# G0-2 백업 무결성
shasum -a 256 -c ~/Knowledge-backup-2026-07-27/CHECKSUMS.txt   # → OK

# G0-3 비밀정보 0건
cd "$HOME/Library/Mobile Documents/com~apple~CloudDocs/heejun_pkm/heejun_PKM" \
  && find . -name '*.pem' -o -name '*.p12' -o -name '*.key' | grep . ; echo "exit=$?"  # → exit=1 (없음)

# G0-4 ★ 쓰기 동결 실효성 (§2.3)
#   diet.log_meal → frozen_for_migration 에러
#   assistant.today → 정상 응답
#   그리고 동결 후 DB 해시가 불변:
shasum -a 256 ~/Knowledge/index/knowledge.db ~/Knowledge/services/diet/diet.json
#   → P1 착수 시점에 재실행해 동일한지 확인

# G0-5 정책 체크 문서에 6개 항목 전부 PASS 기록 (P0-9)
```

#### 롤백
P0는 원본 데이터를 변경하지 않습니다. 되돌릴 것은 둘뿐입니다.
1. `.pem` 원위치 복구 (P0-5)
2. 쓰기 동결 커밋 revert (P0-8) — **P1 게이트 통과 후 정상 절차로 실행**

#### 하지 말 것
- Swift 코드 삭제 (P7)
- Supabase 스키마 생성 (P1)
- Next.js 스캐폴딩 (P4a)

---

### P1 — 스키마 이식 + 데이터 마이그레이션

#### 입력
- `Packages/KnowledgeIndex/Sources/KnowledgeIndex/Schema.swift` (원본 DDL)
- `~/Knowledge-backup-2026-07-27/knowledge.db`
- `~/Knowledge/services/diet/diet.json`, `~/Knowledge/services/inbox/inbox.json`
- `~/Knowledge/config/{features.json,app.json}`
- `docs/DATA_INVENTORY_2026-07-27.md` (목표 행수)

#### 작업 단계

**P1-1. Supabase 프로젝트 생성** — 리전은 서울/도쿄 중 지연이 낮은 쪽. **오너 승인 후 진행.**

**P1-2. DDL 작성 → `web/supabase/migrations/001_init.sql`**

아래는 **초안**입니다. 원본 `Schema.swift`와 대조하며 확정하세요. 변경 원칙: **미팅 컬럼 제거, 타입 현대화(TEXT ts → timestamptz, INTEGER bool → boolean), owner_id 추가, 그 외는 1:1 유지.**

```sql
create extension if not exists pg_trgm;
-- pgvector는 P1에서 활성만 확인, 컬럼은 만들지 않음 (C-7)

-- 공통: 단일 사용자 + RLS. owner_id는 P3에서 정책이 붙는다.
-- P1 시점에는 컬럼만 만들고 RLS는 아직 켜지 않는다(마이그레이션 편의). P3에서 켠다.

create table settings (                        -- 방향성 §6.5.4 P-1
  owner_id uuid not null default auth.uid(),
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, key)
);

create table connected_source (
  id           text primary key,
  owner_id     uuid not null default auth.uid(),
  source_type  text not null,
  root_path    text,
  label        text,
  enabled      boolean not null default true,
  last_sync_at timestamptz,
  last_error   text,
  unit_count   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table knowledge_unit (
  unit_id      text primary key,
  owner_id     uuid not null default auth.uid(),
  source_type  text not null,                  -- 'obsidian' | 'notes'
  title        text,
  scope        text not null default 'personal',
  sot_kind     text not null,                  -- 'vault_md' | 'notes_app'
  sot_ref      text not null,
  content_hash text,
  in_corpus    boolean not null default true,
  rag_eligible boolean not null default true,
  updated_at   timestamptz not null default now()
  -- meeting_status 제거 (F-1)
);
create index on knowledge_unit (source_type);
create index on knowledge_unit (rag_eligible, in_corpus);

create table knowledge_chunk (
  chunk_id     text primary key,
  owner_id     uuid not null default auth.uid(),
  unit_id      text not null references knowledge_unit(unit_id) on delete cascade,
  ordinal      integer not null,
  text         text not null,
  content_hash text
  -- t_start_ms / t_end_ms 제거 (오디오 전용, F-1)
);
create index on knowledge_chunk (unit_id);

create table note_mirror (
  notes_id      text primary key,
  owner_id      uuid not null default auth.uid(),
  folder        text,
  title         text,
  body_text     text,
  content_hash  text,
  body_status   text not null default 'ok',
  mirror_not_sot boolean not null default true,
  updated_at    timestamptz not null default now()
);

create table source_pointer (
  id            text primary key,
  owner_id      uuid not null default auth.uid(),
  source_type   text not null,
  external_id   text not null,
  title         text,
  scope         text not null default 'personal',
  notes_id      text,
  vault_rel_path text,
  updated_at    timestamptz not null default now(),
  unique (source_type, external_id)
  -- meeting_id 제거 (F-1)
);

-- 검색: fts_docs 대체. unit 1:1 유지 (C-6)
create table search_doc (
  doc_id      text primary key,
  owner_id    uuid not null default auth.uid(),
  source_type text not null,
  title       text,
  body        text,
  tsv tsvector generated always as (
    to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(body,''))
  ) stored
);
create index search_doc_tsv_idx   on search_doc using gin (tsv);
create index search_doc_title_trgm on search_doc using gin (title gin_trgm_ops);
create index search_doc_body_trgm  on search_doc using gin (body  gin_trgm_ops);

-- diet: diet.json → 테이블화
create table diet_meal (
  id uuid primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, note text, items jsonb not null default '[]',
  kcal numeric, protein_g numeric
);
create table diet_workout (
  id uuid primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, kind text, minutes integer, intensity text
);
create table diet_metric (
  id uuid primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, weight_kg numeric, sleep_h numeric
);
-- goals / profile은 단일 행이므로 settings 테이블에 jsonb로 저장한다
-- (key='diet.goals', key='diet.profile') — 별도 테이블 금지: 스키마 증식 방지

-- D-3 확정: default-deny 상태기계 적용 대상 ①
create table inbox_item (
  id uuid primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null default now(),
  text text not null,
  status text not null default 'open',        -- open|promoting|promoted|promote_failed
  promoted_path text,
  attempts integer not null default 0,        -- 재시도 상한 (원본 max_stage_attempts 계승)
  error_code text,
  heartbeat_at timestamptz,                   -- 고아 회수 판정용 (원본 R2/R3 계승)
  updated_at timestamptz not null default now()
);

-- D-3 확정: default-deny 상태기계 적용 대상 ②
create table ingest_job (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  kind text not null,                         -- 'corpus_sync' | 'search_reindex'
  status text not null default 'queued',      -- queued|running|done|failed
  attempts integer not null default 0,
  error_code text,
  heartbeat_at timestamptz,
  detail jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on ingest_job (status, heartbeat_at);

-- 상태 전이 감사 로그 (원본 pipeline_events의 축소 계승)
create table state_event (
  id bigserial primary key,
  owner_id uuid not null default auth.uid(),
  subject_kind text not null,                 -- 'inbox_item' | 'ingest_job'
  subject_id text not null,
  ts timestamptz not null default now(),
  from_status text, to_status text not null,
  rule text,                                  -- 'R2' 등 복구 규칙 id
  error_code text
);
create index on state_event (subject_kind, subject_id);

create table llm_answer_cache (
  cache_key   text primary key,
  owner_id    uuid not null default auth.uid(),
  question    text not null,
  answer      jsonb not null,
  provider    text,
  created_at  timestamptz not null default now()
);
create index on llm_answer_cache (created_at);
```
- `meeting`, `action_item`, `chunk_vector`는 **생성하지 않습니다** (F-1, C-7). `pipeline_events`는 `state_event`로 축소 계승합니다(D-3).
- `schema_version`은 Supabase 마이그레이션이 대체하므로 불필요.
- **RLS는 P1에서 켜지 않습니다.** 마이그레이션 편의를 위해 컬럼만 만들고, P3에서 일괄 활성화합니다. **따라서 P1 완료 후 P3 전까지 Vercel을 public으로 배포하지 마세요**(§0.3).

**P1-3. 마이그레이션 스크립트 → `web/scripts/migrate-from-sqlite.ts`**
- 입력은 **백업본**(`~/Knowledge-backup-2026-07-27/knowledge.db`)을 읽습니다. 라이브 DB를 읽지 않습니다.
- 변환 규칙:
  - ISO8601 문자열 → `timestamptz` (원본은 UTC `Z` 표기 — 타임존 손실 금지)
  - `INTEGER 0/1` → `boolean`
  - `sot_ref`가 `Meetings/`로 시작하는 unit **7건 제외** (F-1) 및 제외 수치를 로그로 출력
  - `chunk_vector` **미이관** (C-7)
  - `fts_docs` → `search_doc` (doc_id/source_type/title/body 그대로)
  - `diet.json` → `diet_meal`/`diet_workout`/`diet_metric` + `settings['diet.goals'|'diet.profile']`
    - 원본 `id`는 UUID 문자열이므로 `uuid` 캐스팅
    - `kcal`/`protein_g` 누락 필드는 `null` (0으로 채우지 말 것 — 집계가 달라짐)
  - `inbox.json` → `inbox_item` (`promotedPath` → `promoted_path`, `status` 그대로)
  - `features.json` + `app.json` → `settings` (키 접두: `feature.*`, `app.*`)
    - **이관 제외 키**: `asr.*`, `llm.engine/binary_rel/model_rel`, `ipc.*`, `knowledge_root`, `retention.audio_*`/`raw_audio_*` — 전부 로컬/미팅 전용
    - `cloud_stt`, `blackhole_fallback`, `audio_dir_passphrase`, `embed_transcript_in_vault`, `critic*` → **제외** (F-1)
    - 이관 대상 예: `feature.cloud_llm`, `feature.vector_search`(=false로 강제, C-7), `feature.notes_ingest`, `app.notes.page_size`, `app.rag.*`
  - `secrets.json` → **DB에 넣지 않습니다.** 환경변수 이름 매핑표만 `docs/ENV_VARS.md`에 생성 (값 없이)
- 스크립트는 **멱등(idempotent)** 이어야 합니다: `on conflict do update`. 재실행 가능해야 게이트를 여러 번 돌립니다.
- 마지막에 **행수 대조 리포트**를 stdout으로 출력합니다.

**P1-4. 검색 — D-4 확정안 구현 (기본 `tsvector`, `pg_trgm`은 플래그 대기)**

> **확정: 게이트는 "현행 대비 recall 하락 0"(동등)입니다. 조사 흡수는 P1 통과 조건이 아닙니다.**
> 동시에 `pg_trgm` 경로를 만들어 두고 `settings` 플래그로 켤 수 있게 합니다. 품질 판단은 P5에서 실사용 후 합니다.

1. **기본 경로 (게이트 대상)**: `to_tsvector('simple')` + `plainto_tsquery` + `ts_rank`.
2. **대기 경로 (구축만)**: `pg_trgm` `similarity()` 기반 쿼리를 같은 인터페이스로 구현.
   - 전환 스위치: `settings['search.mode']` ∈ `{'tsvector', 'trgm', 'hybrid'}`, **기본값 `'tsvector'`**.
   - `hybrid` = tsvector 결과 ∪ trgm 결과, trgm 점수로 재랭킹.
   - **P1에서는 `'tsvector'` 외의 값을 기본값으로 두지 마세요.** 게이트 대상이 흔들립니다.
3. **비교 리포트 작성 → `docs/FTS_COMPARISON_2026-07.md`** (게이트는 아니지만 P5 판단 근거로 필수)
   - P0 검색 골든(쿼리 30개)을 세 모드로 각각 실행.
   - 현행 FTS5 결과를 정답 집합으로 보고 쿼리별 recall/precision을 표로 기록.
   - 방향성 §5.1 사례를 **반드시 포함**: `결제`(현행 32건) / `결제를`(현행 3건).
     `결제` 검색에 `결제를/결제가/결제는` 문서가 잡히는지를 모드별로 표기 → P5 전환 결정의 근거.
   - 리포트 말미에 **"P5에서 확인할 것"** 3줄: ① 체감 개선 여부 ② trgm 오탐(무관 문서 혼입) 정도 ③ 응답 지연 차이.

**P1-5. 쓰기 동결 해제 (§2.3) — 게이트 전부 통과한 뒤에만**
1. G1-1~G1-5 통과 확인.
2. P0-8 동결 커밋을 revert (SHA는 `docs/DATA_INVENTORY_2026-07-27.md`에 기록되어 있음).
3. **단, 이 시점에도 웹은 아직 없습니다.** Mac 앱으로 다시 기록하면 Supabase와 SQLite가 갈라집니다.
   → **권장: 동결을 해제하지 말고 P4b 완료까지 유지.** revert는 "언제든 풀 수 있다"는 안전장치이지 즉시 실행할 절차가 아닙니다.
   → 오너가 일상 기록을 재개해야 한다면 **Mac 앱이 아니라 Supabase가 SoT**가 되도록 P4b를 앞당기는 것이 정답입니다.

#### 산출물
- `web/supabase/migrations/001_init.sql`
- `web/scripts/migrate-from-sqlite.ts`
- `web/lib/db/search.ts` (tsvector / trgm / hybrid 3모드, 기본 tsvector)
- `docs/FTS_COMPARISON_2026-07.md`
- `docs/ENV_VARS.md` (이름만)

#### 게이트
```
G1-1  행수 일치: knowledge_unit(=인벤토리 목표치) / knowledge_chunk / note_mirror 19 /
      source_pointer / search_doc / diet_meal 25 / diet_workout 8 / diet_metric 8 / inbox_item 2
      → 마이그레이션 리포트가 목표치와 100% 일치
G1-2  멱등: 스크립트 2회 실행 후 행수 불변
G1-3  ★ 검색 품질(D-4 확정 기준): search.mode='tsvector' 에서
      30쿼리 중 현행 FTS5 대비 recall 하락 0건 → PASS
      (조사 흡수는 P1 통과 조건 아님. trgm 결과는 리포트에만 기록)
G1-4  검색 모드 전환: settings['search.mode']를 'trgm'/'hybrid'로 바꿔도
      런타임 오류 없이 결과가 반환됨 (품질 무관, 경로 존재만 확인)
G1-5  샘플 무결성: 무작위 unit 10건의 title/sot_ref/content_hash가 SQLite와 문자 단위 일치
G1-6  동결 유지 확인: G0-4의 DB 해시가 P0 시점과 동일 (그 사이 쓰기가 없었음)
```

#### 롤백
Supabase 테이블 전체 `drop` 후 마이그레이션 재실행. 원본은 읽기전용 백업이므로 손상 불가.

#### 하지 말 것
- RLS 정책 작성 (P3)
- API 라우트 작성 (P4a)
- 검색 알고리즘 "개선" (임베딩·형태소 분석기 도입, 한국어 형태소 사전 등) — **게이트는 동등이지 최고 품질이 아닙니다.** trgm 튜닝에 시간을 쓰지 마세요. 인덱스와 쿼리 경로만 만들고 넘어갑니다(D-4)
- `search.mode` 기본값을 `'trgm'`/`'hybrid'`로 두기

---

### P2 — Vault → Git 프라이빗 레포

> P1과 **병렬 진행 가능**합니다(의존 없음). 단 P0-5(비밀정보 격리) 완료가 절대 선행조건입니다.

#### 작업 단계

**P2-1. 레포 생성 (D-2 확정: `knowledge-vault` 프라이빗, 코드 레포와 분리)** — **오너 승인 후.**
- 분리는 선택이 아닙니다: Obsidian Git 플러그인이 *vault 루트 = git 루트*를 전제합니다.
- **DB 백업은 이 레포에 넣지 않습니다** (D-2b, P2-4).
- `.gitignore`: `.obsidian/workspace.json`, `.DS_Store`, `*.pem`, `*.key`, `*.p12`
- `.gitattributes`: `*.md text eol=lf`, 이미지 `binary`
- 첫 커밋 전 **재스캔** (P0-5 이후 새로 생긴 파일이 있을 수 있음):
  ```bash
  git ls-files -z | xargs -0 grep -lEi 'BEGIN (RSA|EC|OPENSSH|PRIVATE)|api[_-]?key|Bearer ' | head
  ```
  → 출력이 있으면 커밋 중단.

**P2-2. 첨부파일 정책 확정**
- `90 ⚙️ 첨부파일/` 하위 이미지(png/gif)를 그대로 커밋합니다. 총 vault 6.8MB이므로 LFS 불필요.
- **폴더명에 이모지·공백이 포함**되어 있습니다(`10 📥 수집함` 등). 다음을 확인:
  - macOS(NFD) ↔ Git/Linux(NFC) 유니코드 정규화 차이 → `git config core.precomposeunicode true` 설정
  - Vercel 런타임에서 경로 조회 시 정규화 불일치가 생기지 않는지 P4a에서 재확인
- 이 정책을 `knowledge-vault/README.md`에 기록.

**P2-3. Obsidian Git 플러그인 설정**
- 자동 커밋 주기·자동 pull 활성화. 충돌 시 **자동 병합 금지, 수동 해결**로 설정.
- `docs/commit_protocol.md`를 재해석해 `knowledge-vault/COMMIT_PROTOCOL.md`로 이관:
  - 커밋 주체: Obsidian(사람) / 웹(앱 봇) 두 종류
  - 웹에서 편집 시 커밋 메시지 규약: `web: <경로>` 접두 → 충돌 원인 추적 가능
  - 웹 쓰기 경로는 **`10 📥 수집함/` 하위로 한정** (인박스 승격 산출물). 다른 폴더는 웹에서 쓰지 않음 → 충돌 표면 최소화

**P2-4. pg_dump 백업 GitHub Actions — D-2b 확정: 별도 `knowledge-backup` 프라이빗 레포**

> 방향성 §5.2.3의 원안은 "vault 레포가 DB 덤프 보관소를 겸한다"였으나 **번복합니다.**
> `backups/*.sql.gz`가 vault 안에 있으면 Obsidian이 이를 vault 파일로 인식해 검색·그래프·모바일 동기를 오염시킵니다.
> 코드 레포에 두는 안(8.30)도 백업 커밋마다 Vercel 재배포가 트리거되어 무료 빌드 시간을 소모합니다.

- **오너 승인 후** `knowledge-backup` 프라이빗 레포 생성.
- `.github/workflows/db-backup.yml`: 주 1회 스케줄 + `workflow_dispatch` 수동 트리거.
- `pg_dump` 결과를 `backups/knowledge-YYYYMMDD.sql.gz`로 커밋.
- DB 접속 문자열은 **레포 Secrets**에 저장. 워크플로 로그 출력 금지(`--no-password`, `set +x`, 에러 메시지 마스킹).
- 보관 정책: 최근 12개 유지, 초과분 삭제 스텝 포함.
- **복원 절차를 `knowledge-backup/RESTORE.md`에 기록**하고 G2-4에서 1회 실제로 수행합니다. 복원해본 적 없는 백업은 백업이 아닙니다.

**P2-5. keep-alive 핑** (방향성 §5.2.3 / 리스크 "무활동 정지")
- P0-9에서 keep-alive가 유효하다고 확인된 경우에만 구성.
- Vercel Cron(일 1회) → `/api/cron/keepalive` → Supabase에 가벼운 `select 1`.
- **P4a에서 라우트를 만들 때 함께 구현**하고, P2에서는 설계만 확정합니다.

#### 게이트
```
G2-1 왕복: Obsidian에서 노트 수정 → 커밋/푸시 → 다른 기기 pull → 내용 일치
G2-2 역방향: 레포에서 직접 파일 수정 → Obsidian이 pull로 반영
G2-3 비밀정보: git log 전체 이력에 .pem/키 문자열 0건
     (git log -p | grep -c 'BEGIN .*PRIVATE KEY' → 0)
G2-4 knowledge-backup 레포에서 워크플로 수동 실행 → backups/*.sql.gz 생성
     → 별도 Supabase 브랜치(또는 로컬 postgres)에 실제 복원 1회 성공
     → RESTORE.md 절차대로 재현 가능
G2-5 vault 레포에 백업 파일이 없음: git ls-files | grep -c 'sql.gz' → 0 (D-2b)
```

#### 하지 말 것
- vault 구조 재편(폴더 이름 정리 등). 이건 리팩토링이 아니라 신규 작업입니다.
- 웹에서의 vault 쓰기 구현 (P4a/P5)

---

### P3 — 인증 (Supabase Auth + RLS) — ✅ 완료 (2026-07-27)

> **방향성 §6.5.2: 이 프로젝트에서 실패 확률이 가장 높은 단계입니다.** 전례 0건.
> 그래서 **독립 게이트**로 분리했습니다. "직접 구현"이 아니라 **"설정"** 이라는 점을 계속 확인하세요.

> **★ 이 절은 실행 후 as-built로 갱신되었습니다 (2026-07-27).** 착수 당시 원문에는
> ① 스캐폴드 부재(아래 P3-0), ② 콜백 라우트 누락(P3-3), ③ 마이그레이션 번호·파일명 스테일이
> 있었고, 그중 ②가 실제 로그인 실패로 이어졌습니다. 경위는 §P3 회고 참조.

#### 작업 단계

**P3-0. Next.js 스캐폴드 ← 원문에 없던 선행 단계 (P4a-1에서 이관)**
- 원문은 P4a-1에 `create-next-app`을 두었으나, P3-3이 미들웨어·로그인 페이지를 요구하므로
  **스캐폴드 없이는 P3를 착수할 수 없다.** 실제로 P3에서 먼저 생성했다.
- `web/`에 App Router + TypeScript로 생성. **Tailwind·ESLint 미도입**(기존에 없던 의존성을
  리팩토링 중 새로 들이지 않는다 — F-6).
- 기존 `web/package.json`·`tsconfig.json`은 P1 스크립트(`scripts/`, `lib/`)용이므로
  **덮어쓰지 말고 병합**한다. 병합 후 `npm run migrate`가 여전히 동작하는지 확인할 것.
- 실측 버전: `next@16.2.12`, `react@19.2.4`, `@supabase/ssr@^0.12.3`, `@supabase/supabase-js@^2.110.8`.

**P3-1. Auth 방식 확정**
- **매직링크(이메일 OTP)** 를 1순위로 합니다. 비밀번호 저장·재설정 흐름을 아예 만들지 않아도 됩니다.
- 사용자 1명 → Supabase Auth 설정에서 **신규 가입 비활성화(Disable signup)** 후 오너 계정만 수동 생성. 이게 없으면 URL을 아는 누구나 가입해 자기 테넌트를 만듭니다.
- **as-built**: 오너 계정은 `web/scripts/create-owner-user.ts`(service_role,
  `admin.createUser({email, email_confirm:true})`)로 생성. Disable signup은 MCP에 설정 툴이
  없어 **대시보드에서 수동 처리**했고, `GET /auth/v1/settings`의 `disable_signup: true`로 검증 가능하다.

**P3-2. RLS 정책 — 모든 테이블에 예외 없이**
```sql
alter table settings           enable row level security;
alter table connected_source   enable row level security;
alter table knowledge_unit     enable row level security;
alter table knowledge_chunk    enable row level security;
alter table note_mirror        enable row level security;
alter table source_pointer     enable row level security;
alter table search_doc         enable row level security;
alter table diet_meal          enable row level security;
alter table diet_workout       enable row level security;
alter table diet_metric        enable row level security;
alter table inbox_item         enable row level security;
alter table ingest_job         enable row level security;   -- D-3
alter table state_event        enable row level security;   -- D-3
alter table llm_answer_cache   enable row level security;

-- 각 테이블에 대해 동일 패턴
create policy owner_all on <table>
  for all to authenticated          -- ← as-built: 원문에 없던 TO 절 추가
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
```
- **`enable row level security`를 빠뜨린 테이블이 하나라도 있으면 그 테이블은 anon 키로 전부 읽힙니다.** 게이트 G3-3이 이걸 잡습니다.
- **마이그레이션 파일: `web/supabase/migrations/004_rls.sql`** (원문은 `002_rls.sql`이라고
  했으나 P1 이후 002·003이 검색 기능에 쓰여 번호가 밀렸다. **파일명을 기억으로 조립하지 말고
  `ls web/supabase/migrations/`로 다음 번호를 확인할 것.**)
- `to authenticated`는 Supabase 보안 체크리스트 권고다. TO 절이 없으면 anon 역할도 정책
  평가 대상이 되어 의도가 흐려진다.
- **owner_id placeholder 교체**: RLS를 켜면 P1이 심어둔 placeholder
  (`00000000-...-0001`) 행은 실제 오너에게 보이지 않는다. 오너 계정 생성 직후
  14개 테이블에 UPDATE 1건씩 실행해야 한다 — 절차·실측 결과는 `docs/ENV_VARS.md`.

**P3-3. Next.js 통합**
- `@supabase/ssr` 사용. 서버 컴포넌트/라우트 핸들러/미들웨어 각각의 클라이언트를 분리 생성.
  → as-built: `web/lib/supabase/{client,server,proxy}.ts`
- **미들웨어 파일명은 `proxy.ts`다** (원문 `middleware.ts`는 Next 15 이하 표기).
  Next 16은 루트 `proxy.ts`에서 `export async function proxy()` + `config.matcher`.
  빌드 로그에 `ƒ Proxy (Middleware)`가 찍히면 인식된 것이다.
- `(app)` 그룹 전체를 보호, 미인증 시 `/login` 리다이렉트.
- **키 사용 규칙 (위반 시 전체 무의미):**
  | 키 | 사용처 |
  |---|---|
  | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | 브라우저·서버 모두. RLS가 걸린 상태에서만 안전 |
  | `SUPABASE_SERVICE_ROLE_KEY` | **마이그레이션·관리 스크립트 전용.** 앱 코드(`web/app`, `web/lib`)에서 import 금지 |
- 보호 대상에서 제외할 경로: `/login`, **`/auth/callback`, `/auth/confirm`**,
  `/api/cron/*`(별도 시크릿 헤더로 보호), `/api/health/ingest`(Shortcuts용 — **별도 토큰 인증** 필요)

**P3-3b. ★ 인증 콜백 라우트 — 원문 누락 항목 (실제 로그인 실패의 원인)**

> 매직링크는 "리다이렉트만" 만들면 동작하지 않는다. Supabase가 인증을 끝낸 뒤
> **일회용 자격증명을 URL 파라미터로 돌려보내는데, 그것을 세션 쿠키로 교환하는 라우트가
> 없으면** 미들웨어가 그 요청을 다시 `/login`으로 튕겨내고 자격증명은 버려진다.
> 사용자 눈에는 "링크를 눌렀는데 로그인 화면이 그대로"로 보인다.

두 가지 흐름을 **모두** 지원해야 한다:

| 흐름 | 파라미터 | 라우트 | 교환 API |
|---|---|---|---|
| PKCE (브라우저에서 `signInWithOtp` 호출 시 기본) | `?code=` | `app/auth/callback/route.ts` | `exchangeCodeForSession(code)` |
| token hash (서버에서 발급한 링크. 브라우저 verifier 쿠키 불필요) | `?token_hash=&type=` | `app/auth/confirm/route.ts` | `verifyOtp({type, token_hash})` |

- **매직링크가 반드시 콜백 경로로 떨어지지는 않는다.** 기본값은 Site URL 루트(`/`)다.
  따라서 `proxy.ts`는 미인증 요청을 무조건 `/login`으로 보내지 말고,
  **`code`/`token_hash` 파라미터가 있으면 해당 콜백 라우트로 넘겨야** 한다.
  이렇게 하면 대시보드의 Site URL·Redirect 허용목록 설정과 무관하게 동작한다.
- 로그인 페이지에서는 `signInWithOtp({ email, options: { emailRedirectTo: origin + '/auth/callback' } })`.

**P3-3c. 로컬 개발 시 이메일 발송 제한 우회**
- Supabase 무료 티어 기본 SMTP는 발송 건수 제한이 매우 낮아, 로그인 테스트를 몇 번 하면
  `email rate limit exceeded`로 막힌다. **기다리지 말 것.**
- `web/scripts/generate-magic-link.ts` — `admin.generateLink()`는 **메일을 보내지 않고**
  토큰만 만들므로 제한과 무관하다. 출력된 `/auth/confirm?token_hash=...` URL을 브라우저에
  붙여넣으면 로그인된다. **로컬 전용 도구이며 service_role 키를 쓴다.**

**P3-4. Shortcuts 인그레스 인증**
- `health.ingest`는 브라우저 세션이 없으므로 매직링크로 보호 불가.
- **긴 랜덤 토큰(≥32바이트)을 환경변수에 두고 `Authorization: Bearer` 검증** + 해당 라우트는 `service_role` 없이 `owner_id`를 서버에서 고정 주입.
- 토큰은 Shortcuts 앱 안에만 저장. 문서에 값 기록 금지.
- **as-built (미완 — P4a/P4b로 이월)**: P3에서는 환경변수 이름(`INGEST_API_TOKEN`)을
  `ENV_VARS.md`·`ENV_EXAMPLE.txt`에 등재하고 `proxy.ts` 제외 경로에 넣는 데까지만 했다.
  **Bearer 검증 로직과 라우트 본체는 없다** — `/api/health/ingest` 엔드포인트 자체가 아직
  존재하지 않기 때문이다(없는 라우트에 인증만 먼저 넣는 것은 F-6 위반). 토큰 값도 미발급.
  → 라우트를 만드는 Phase에서 **같은 커밋에** 구현할 것.

#### 게이트 — **DB 레이어 차단 증명이 핵심**
```
G3-1  미인증 브라우저로 보호 경로 접근 → /login 리다이렉트
G3-2  유효 매직링크 로그인 → 보호 경로 접근 가능
G3-3  ★ anon 키로 REST 직접 호출 시 전 테이블 0행:
      for t in settings connected_source knowledge_unit knowledge_chunk note_mirror \
               source_pointer search_doc diet_meal diet_workout diet_metric \
               inbox_item ingest_job state_event llm_answer_cache; do
        curl -s "$SUPABASE_URL/rest/v1/$t?select=*&limit=1" \
             -H "apikey: $ANON_KEY" | head -c 200; echo " <= $t"
      done
      → 전부 [] 또는 권한 오류. 한 건이라도 데이터가 나오면 FAIL
G3-4  신규 가입 시도 → 거부됨
      실측 방법: curl "$SUPABASE_URL/auth/v1/settings" -H "apikey: $ANON_KEY"
      → disable_signup: true 확인 (가입을 실제로 시도해 쓰레기 계정을 만들지 말 것)
G3-5  service_role 키가 클라이언트 번들에 없음:
      grep -r "service_role" web/app web/lib | grep -v "\.md"  → 출력 없음
      그리고 빌드 산출물 검사: grep -rl -- "$SECRET" web/.next  → 출력 없음
      ※ 검사 함정 2가지:
        · `grep ... | head` 로 판정하지 말 것 — 파이프라인 종료코드는 head의 것이라 항상 0이다.
        · 키 앞부분(JWT 헤더 `eyJhbGciOi...`)은 anon 키와 동일해 오탐이 난다. 값 전체로 검색할 것.
        · 대조군: anon 키는 `.next/static`에서 **발견되어야** 정상이다(공개 키). 안 나오면 검사 자체가 무의미한 것이다.
```

**실측 결과 (2026-07-27) — 전부 PASS**

| 게이트 | 결과 |
|---|---|
| G3-1 | `/` → 307 → `/login` |
| G3-2 | 링크 클릭 → `sb-<ref>-auth-token` 쿠키 발급 → 보호된 `/` 200 (리다이렉트 없음) |
| G3-3 | 14개 테이블 전부 `[]` |
| G3-4 | `disable_signup: true` |
| G3-5 | `.next` 전체에 secret 키 없음 (대조군으로 검사 유효성 확인) |
| 추가 | 로그인 상태 조회 시 `knowledge_unit` 236 / `search_doc` 236 / `diet_meal` 25 / `settings` 8행 — P1 이관량과 일치. **RLS가 오너 본인을 막지 않는 것까지 확인.** |

> **G3-2 단서**: 위 검증은 `token_hash` 경로(`/auth/confirm`)로 수행했다.
> 이메일 발송 경로(PKCE `code` → `/auth/callback`)는 라우팅만 검증했고 실제 코드 교환은
> 발송 제한 때문에 미검증이다. P4a 착수 시 한 번 확인할 것.

#### 하지 말 것
- 자체 세션/JWT/CSRF 구현 (Supabase가 처리)
- `owner_id`를 클라이언트가 보낸 값으로 채우기 (**항상 `auth.uid()` 기본값 또는 서버 주입**)
- RLS 없이 "일단 동작하게" 배포
- **미인증 요청을 무조건 `/login`으로 리다이렉트** (P3-3b 참조 — 인증 자격증명까지 버려진다)

#### P3 회고 — 왜 두 번 헛돌았나 (재발 방지)

1. **원문에 콜백 라우트가 없었다.** 그러나 매직링크에 콜백이 필요한 것은 기본이므로,
   플랜의 공백이 아니라 **구현자가 메꿨어야 할 부분**이다. 플랜은 체크리스트지 명세가 아니다.
2. **실패 시 로그를 먼저 보지 않고 추측했다.** 이게 실제 낭비의 원인이다.
   MCP `get_logs(service:"auth")` 한 번이면 다음이 바로 보였다:
   ```
   path=/verify  status=303  auth_event: {action: "login", actor_username: ...}
   ```
   = **Supabase는 로그인을 성공시켰다 → 문제는 앱 쪽 다운스트림**. 이 한 줄을 먼저 확인했으면
   이메일 템플릿을 고치라는 잘못된 안내와 콜백 형식 오판(둘 다 헛수고)을 건너뛸 수 있었다.
   → **인증이 실패하면 코드를 고치기 전에 auth 로그부터 읽는다.**

---

### P4a — 읽기 API 계층

#### 원칙
- **메서드명 보존** (방향성 §6): 기존 `core.* / assistant.* / knowledge.* / inbox.* / timeline.*` 이름을 그대로 유지합니다. UI 재작성 범위가 줄고, 골든 스냅샷이 그대로 정답으로 쓰입니다.
- 구현: `/api/rpc` 단일 라우트에서 `{method, params}` 디스패치 + 주요 메서드는 REST 별칭도 제공(§8).
- **응답 JSON 형태를 골든과 동일하게 맞춥니다.** 필드 추가·이름 변경·정렬 변경 전부 금지.

#### 착수 전 인지 (P3 실행 결과 반영, 2026-07-27)

1. **`create-next-app`은 이미 P3-0에서 완료됐다.** 다시 하지 말 것 — 기존
   `package.json`/`tsconfig.json`을 덮어써서 P1 스크립트를 깨뜨린다.
   Vercel Root Directory = `web` 설정만 남아 있다. **배포는 P3 인증이 붙은 상태로만.**
2. **★ `proxy.ts`는 현재 모든 미인증 요청을 `/login`으로 307 리다이렉트한다.**
   게이트 **G4a-5는 `/api/rpc`에 401을 요구**하므로 그대로면 통과하지 못한다.
   `/api/*` 경로는 리다이렉트 대신 `401`(JSON)을 반환하도록 분기해야 한다.
   제외 경로(`/api/cron/*`, `/api/health/ingest`)는 각자의 인증을 쓰므로 별도 처리.
3. `/`는 현재 P3 검증용 5줄짜리 플레이스홀더다(`web/app/page.tsx`). P5에서 Hub로 대체된다.
4. **`health.ingest`는 P4a가 아니라 P4b다(2026-07-28 정정).** 원본 Swift
   (`MobileHTTPServer.swift`의 `health.ingest` 핸들러)는 `DietStore.swift`의
   `ingestHealthSamples(_:)`를 호출하고, 그 안에서 이 표의 `diet.log_workout`/
   `diet.log_metric`(P4b, §8)에 해당하는 `logWorkout`/`logMetric`을 직접
   호출한다. `logMetric`은 추가로 활성 단식 중이면 `morning_fasted` 태그를
   붙이는 로직이 있어 P4b의 `FastingPrefs`(task 12)도 참조한다. 라우트 본체는
   P4b에서 diet 쓰기 메서드들과 함께 구현한다(§P4b 작업 단계 4). `/api/health/ingest`의
   Bearer 토큰(`INGEST_API_TOKEN`) 검증 자체는 이때 함께 만든다 — 제외 경로
   지정(`proxy.ts`)과 환경변수 이름만 P3에서 먼저 정해뒀다.
   `health.sync_status`는 원본이 상태와 무관한 정적값을 반환하므로 이 문제가
   없다 — P4a에 그대로 남는다.

#### 작업 단계
1. `lib/settings.ts` — 방향성 §6.5.4 **P-1 패턴**: DB `settings` 로드 → 모듈 스코프 캐시 → TTL. 서버리스에서 인스턴스별 캐시임을 주석으로 명시하고, 설정 변경 시 무효화 경로(`?refresh=1`)를 둡니다.
2. `lib/db/` — 쿼리 함수. **컴포넌트에서 SQL 직접 작성 금지.**
3. 읽기 메서드 구현 (§8 표의 읽기 계열):
   - `core.ping/health/services`
   - `assistant.today` / `assistant.week_review` / `assistant.gaps` / `assistant.gaps.evening`
   - `timeline.list`
   - `knowledge.search` (P1에서 확정한 D-4 방식)
   - `corpus.status`
   - `inbox.list`
   - `diet.day_summary` / `diet.dashboard` / `diet.week_review` / `diet.goals*` / `diet.profile.get` / `diet.fasting.status`
     - ※ diet 도메인 로직 본체는 P4b. P4a에서는 **조회에 필요한 최소 범위만** 번역합니다.
4. **★ D-3 확정: default-deny 상태기계 이식 → `web/lib/domain/state-machine.ts`**

   원본 `PipelineGraph.swift`(161줄) + `CrashRecovery.swift`(108줄)의 **구조를 그대로** 옮기되, 상태 집합만 교체합니다. 원본 Swift는 P7에서 `legacy/`로 아카이브합니다.

   **이식하는 것 (4가지 성질):**
   | 원본 성질 | 이식 형태 |
   |---|---|
   | 합법 엣지를 데이터로 선언 | `TRANSITIONS: {from, to, guard}[]` 배열 |
   | **default-deny** (선언 안 된 전이는 거부) | `canTransition()`이 배열에 없으면 무조건 false |
   | **와일드카드 → 최종상태 금지** (원본 S11) | `(*, 'promoted')`, `(*, 'done')` 엣지 선언 금지 |
   | 크래시 복구 규칙 R1–R4 | 고아 회수 함수 + `state_event.rule`에 규칙 id 기록 |

   **상태기계 ① `inbox_item`**
   ```
   open       → promoting        guard: userRequest
   promoting  → promoted         guard: vaultCommitOk      ← 유일한 promoted 진입 경로
   promoting  → promote_failed   guard: commitError|timeout
   promote_failed → promoting    guard: retryUnderMaxAttempts
   promote_failed → open         guard: userOnly
   open       → (삭제)           guard: userOnly
   ```
   - `inbox.promote` = vault Git 레포에 md 생성 + 커밋. Git 쓰기는 **GitHub Contents API** 사용(서버리스에 git 바이너리 없음). 커밋 메시지 `web: ...` 규약(P2-3), 쓰기 경로는 `10 📥 수집함/` 한정.
   - **복구 규칙 R2′**: `status='promoting'` 이고 `heartbeat_at`이 임계(예: 120초) 초과 → GitHub API로 해당 경로 존재를 확인해 `promoted`(커밋은 됐는데 응답 전에 죽음) 또는 `promote_failed`로 회수. **함수가 커밋 직후 죽는 경우가 실제로 발생합니다.**
   - **복구 규칙 R3′**: `attempts >= max_stage_attempts`(원본 `Thresholds` 키 계승) → `promote_failed` 고정, 자동 재시도 중단.

   **상태기계 ② `ingest_job`** (`corpus.sync`, `search.reindex`)
   ```
   queued  → running   guard: workerFree
   running → done      guard: completed
   running → failed    guard: error|timeout
   failed  → queued    guard: retryUnderMaxAttempts
   ```
   - **복구 규칙 R2″**: `running` + heartbeat 만료 → `failed`로 회수 후 재큐잉 가능.
   - 고아 회수는 `pg_cron`(5분 주기) 또는 다음 요청 진입 시 lazy 실행. **상주 워커를 만들지 마세요**(방향성 §4.1-1).

   **모든 전이는 `state_event`에 기록**합니다 — `from_status/to_status/rule/error_code`. 원본 `pipeline_events`의 축소 계승이며, 서버리스에서 "왜 여기서 멈췄나"를 사후에 알 수 있는 유일한 수단입니다.

   **테스트를 같은 커밋에** 작성합니다(원본 S02/S02b/S11의 정신을 계승):
   - 선언되지 않은 임의 전이 20개가 전부 거부됨 (default-deny)
   - `open → promoted` 직행이 거부됨 (와일드카드 금지)
   - heartbeat 만료 시나리오 4종이 기대 상태·기대 규칙 id로 회수됨
5. `/api/cron/keepalive` (P2-5) + Vercel Cron 등록.
6. `lib/redaction.ts` — `docs/redaction_patterns.json`·`redaction_allowlist.json`을 **데이터 파일 그대로 로드**. 로직만 TS로 옮깁니다.

#### 게이트
```
G4a-1 골든 회귀: 읽기 메서드 전부 → 정규화 후 P0 골든과 diff 0
      npm run test:regression -- --scope=read
G4a-2 inbox 왕복: create → promote → vault 레포에 커밋 확인 → list에서 promoted
G4a-3 ★ 상태기계(D-3):
      · 선언되지 않은 전이 20종 전부 거부 (default-deny)
      · open → promoted 직행 거부
      · promote를 커밋 직후 강제 중단 → heartbeat 만료 → R2′로 promoted 회수
      · attempts 상한 도달 → promote_failed 고정, 자동 재시도 없음
      · 위 전이가 전부 state_event에 rule id와 함께 기록됨
G4a-4 ingest_job: corpus.sync 실행 중 중단 → 고아 running이 R2″로 failed 회수 → 재큐잉 성공
G4a-5 인증: 로그아웃 상태에서 /api/rpc 호출 → 401 (200 + 빈 데이터 아님)
      ※ 307 리다이렉트도 FAIL이다. P3의 proxy.ts 기본 동작이 리다이렉트이므로
        /api/* 분기를 추가하지 않으면 여기서 걸린다 (위 "착수 전 인지" 2번).
G4a-6 검색: settings['search.mode']='tsvector' 상태에서 골든 검색 결과 재현 (D-4)
```

---

### P4b — Diet API + 도메인 번역

> C-3: 단일 최대 덩어리(약 2,000 LOC 상당). 별도 Phase로 분리한 이유입니다.

#### 작업 단계
1. **번역 순서 (의존성 순):**
   `thresholds.ts` → `diet-presets.ts` → `nutrition-calc.ts` → `diet-profile.ts` → `diet-store.ts`
2. **번역 규칙:**
   - **1:1 번역**입니다. 리팩토링·개선·이름 정리 금지. Swift 함수명 → camelCase 그대로.
   - 부동소수 계산은 반올림 시점까지 원본과 동일하게. (`assistant.today`의 kcal/protein 표시가 골든과 어긋나는 원인 1순위)
   - 날짜 경계 처리(하루의 시작, 주간 리뷰 범위)는 원본의 타임존 처리를 그대로 재현. 원본이 로컬 타임존을 쓰면 서버(UTC)에서 달라집니다 → **명시적으로 `Asia/Seoul` 고정**하고 그 결정을 코드 주석에 남깁니다.
3. **각 파일마다 유닛 테스트를 같은 커밋에** 작성. 원본 Swift 테스트가 있으면 케이스를 그대로 이식합니다:
   ```bash
   ls Packages/KnowledgeCore/Tests/KnowledgeCoreTests/
   ```
4. 나머지 diet 메서드 구현: `log_meal/log_workout/log_metric`, `delete_*`, `estimate_nutrition`, `suggest`, `coach`, `plan`, `fasting.*`, `goals.set`, `profile.set`, `diet.json`(디버그 전용으로 축소)
   - `diet.estimate_nutrition`은 LLM 의존 → **P6까지는 규칙 기반 fallback만** 동작시키고 TODO 표기.
   - `diet.fasting.*`은 분 단위 스케줄 필요 → `pg_cron` 사용(방향성 §5.2.2). Vercel Cron으로 시도하지 마세요.
   - **`health.ingest`(§8, 2026-07-28 P4a→P4b 재분류)도 여기서 함께 구현**: `POST /api/health/ingest`,
     `INGEST_API_TOKEN` Bearer 검증(P3에서 제외 경로만 지정됨), 원본 `ingestHealthSamples(_:)`를
     1:1 이식 — `log_workout`/`log_metric` 코드를 그대로 재사용하고 `logMetric`의
     `morning_fasted` 자동 태그는 `fasting.*`(같은 단계) 이식 이후에 연결할 것.

#### 게이트
```
G4b-1 도메인 유닛 테스트 전부 통과 (원본 Swift 테스트 케이스 이식분 포함)
G4b-2 골든 회귀: diet 계열 읽기 메서드 diff 0
G4b-3 쓰기 왕복: log_meal → day_summary 총합 반영 → delete_meal → 원복
G4b-4 pg_cron으로 등록한 단식 리마인더가 실제 발화
```

---

### P5 — 웹 UI

#### 참조
- 기존 뷰 구조: `Packages/KnowledgeUI/Sources/KnowledgeUI/Views/{HomeView, SearchView, ChatView, DietView, ReviewInboxView, SettingsView, MoreHubView}.swift`
- 디자인 토큰: `Packages/KnowledgeUI/Sources/KnowledgeUI/TossTheme.swift` → `web/app/theme.css`로 계승
- **`RecordView.swift` / `MeetingDetailView.swift` / `SourcesView.swift`(캡처 부분)는 이식 대상 아님** (F-1)

#### 작업 단계
1. 라우트: `/`(Hub) · `/search` · `/chat` · `/diet` · `/inbox` · `/settings`
2. **Hub = `assistant.today` 한 번 호출**로 그리도록 유지(기존 설계 그대로). 화면당 호출 수를 늘리지 마세요 — 무료 티어에서 요청 수가 곧 비용입니다.
3. PWA: `manifest.json` + 서비스워커(오프라인 셸만, 데이터 캐시 금지 — 단일 사용자에서 stale 데이터가 더 위험).
4. 모바일 우선 레이아웃. 하단 탭 = 기존 macOS 사이드바 항목과 1:1.
5. Web Push는 **P5 범위 밖**입니다(방향성 §3-B). 하지 마세요.
6. **★ D-4 후속 판단 — 검색 모드 확정 (P5에서만 하는 결정)**
   - P1에서 `search.mode`를 3모드로 만들어 두고 기본값 `'tsvector'`로 두었습니다.
   - 실제 검색 화면에서 **동일 쿼리를 3모드로 각각 써보고** `docs/FTS_COMPARISON_2026-07.md`의 "P5에서 확인할 것" 3항목을 채웁니다: ① 체감 개선 ② trgm 오탐 정도 ③ 응답 지연.
   - `settings['search.mode']` 값 하나만 바꾸면 되므로 **코드 변경 없이** 전환합니다.
   - 결정 결과를 `docs/FTS_COMPARISON_2026-07.md` 말미에 3줄로 기록하고 끝냅니다. **형태소 분석기 도입 등 새 작업으로 번지지 않게 하세요**(기능 동결, F-6).

#### 게이트
```
G5-1 폰 브라우저에서 URL만으로 로그인 → Hub·검색·Chat·Diet·Inbox 전부 동작
G5-2 데스크톱 브라우저 동일
G5-3 PWA 설치 후 홈 화면 아이콘으로 실행 가능
G5-4 Lighthouse: 성능/접근성 각 80 이상 (완벽 아님, 회귀 방지선)
G5-5 D-4 후속 판단 완료: search.mode 최종값이 settings에 반영되고 근거 3줄이 문서에 기록됨
```

---

### P6 — 생성 경로 이식

#### 참조 (Swift 원본)
`LLMProviderCatalog.swift`(188) · `LLMRouter.swift`(169) · `CloudLLMClient.swift`(232) · `LLMAnswerCache.swift`(131) · `ExtractiveSummarizer.swift`(126) · `KnowledgeRAG.swift`(299) · `LocalRetrieve.swift`(319) · `TextChunker.swift`(156) · `RedactionPreflight.swift`(98)

#### 작업 단계
1. `config/examples/llm_providers.json`(order: groq → gemini → openrouter)을 **그대로 `settings` 테이블 또는 레포 JSON으로** 옮깁니다. 카탈로그 구조를 재설계하지 마세요 — 이미 검증됨(방향성 §6.5.4 P-3).
2. API 키 → **Vercel 환경변수** (`GROQ_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`). `secrets.json` 개념 폐기.
3. `LLMAnswerCache` → `llm_answer_cache` 테이블. 캐시 키 생성 규칙을 원본과 동일하게.
4. throttle: 원본은 프로세스 메모리 기반일 가능성이 높습니다 → **서버리스에서는 무효**. DB 카운터 또는 `pg_cron` 기반 윈도우로 재구현. 이건 **의도된 재설계**이며 유일하게 허용되는 재설계입니다.
5. `knowledge.ask` / `knowledge.ask.fast`: 검색(P1 확정 방식) → 컨텍스트 조립(`TextChunker`) → LLM → **실패 시 `ExtractiveSummarizer`**.
6. **extractive fallback은 1급 경로**입니다(방향성 §9). 예외 처리의 곁가지가 아니라 명시적 분기여야 하고, 테스트로 강제합니다.
7. `RedactionPreflight`를 LLM 호출 **직전**에 적용 (F-5의 "redaction preflight 유지" 약속).

#### 게이트
```
G6-1 정상: knowledge.ask 응답에 출처(doc_id) 포함
G6-2 캐스케이드: groq 키를 무효화 → gemini로 전이 → 응답 성공
G6-3 ★ 전면 실패: 모든 provider 키 무효화 → extractive 요약으로 응답 (에러 아님)
G6-4 캐시: 동일 질문 2회 → 2번째는 provider 호출 0회
G6-5 redaction: 패턴 매칭 텍스트가 외부 요청 본문에 포함되지 않음 (요청 로깅으로 확인)
```

---

### P7 — 레거시 해체

> **되돌리기 어려운 작업이 집중된 Phase입니다. 각 단계마다 사전 승인을 받으세요.**

#### 선행 조건 (전부 충족 후 착수)
- P5 게이트 통과 후 **7일 이상 병행 운영**하며 웹만으로 일상 사용에 문제 없음 (D-5)
- P2-4 DB 백업이 최소 1회 이상 정상 생성·복원 검증됨

#### 작업 단계 (순서 고정 — 역순 금지)
1. **LaunchAgent 중지·제거**
   ```bash
   launchctl list | grep -i knowledge
   launchctl bootout gui/$(id -u)/<label>
   rm ~/Library/LaunchAgents/<label>.plist
   ```
   → **여기서 1일 관찰.** 웹 서비스에 영향 없음을 확인한 뒤 다음 단계.
2. **Swift 소스 아카이브** — 삭제가 아니라 `legacy/`로 이동 + 커밋. `Package.swift`도 함께 이동.
   - 이동 대상: `Packages/`, `Sources/`, `Apps/`
   - `docs/`, `Schemas/`, `evals/`, `config/examples/`는 **남깁니다** (정책 SoT)
   - D-3에 따라 `PipelineGraph.swift`·`CrashRecovery.swift`도 여기서 아카이브됩니다. 이 시점에는 `web/lib/domain/state-machine.ts`가 이미 그 역할을 대체하고 있어야 합니다 — **P4a 게이트 G4a-3이 통과되지 않았다면 이 단계를 진행하지 마세요.**
3. **모델·툴 삭제 (4.4GB)** — 마지막. 되돌리려면 재다운로드가 필요합니다.
   ```bash
   du -sh ~/Knowledge/tools
   rm -rf ~/Knowledge/tools
   ```
4. `~/Knowledge/` 잔여 정리: `audio/ transcripts/ summaries/ cache/`(빈 디렉토리) 제거. `index/`·`services/`·`config/`는 **백업이 있으므로** 제거 가능하나, 최소 30일은 남겨두길 권합니다.
5. iOS 앱: `Apps/KnowledgeMobile` 아카이브. 프로비저닝 프로파일·인증서 정리는 오너가 직접(계정 작업).
6. 문서 최종 정합화: `README.md`를 웹 아키텍처 기준으로 갱신. `INSTALL_FIELD.md`·`MOBILE_*` 문서는 `archive/`로.

#### 게이트 — **이것이 프로젝트의 완료 정의**
```
G7-1 ★ Mac 전원 완전 종료 상태에서, 폰 LTE로:
     로그인 → Hub 표시 → 검색 → Chat 응답 → 식사 기록 → 인박스 캡처·승격
     → 전부 성공
G7-2 승격된 인박스가 knowledge-vault 레포에 커밋되어 있음
G7-3 Mac 재부팅 후 knowledged 프로세스가 뜨지 않음 (ps aux | grep knowledged → 없음)
G7-4 ~/Knowledge 용량이 100MB 미만
```

---

## 6. 골든 스냅샷 회귀 세트 설계 (P0-4 상세)

> C-1 때문에 신규 구축합니다. **이것이 리라이트의 유일한 안전망입니다.**

### 6.1 채취 대상
§8 표에서 **읽기(R)** 로 표시된 메서드 전부. 각 메서드마다:
```
web/tests/golden/
  read/assistant.today.json
  read/assistant.week_review.json
  read/timeline.list.json
  read/diet.day_summary.json
  ...
  search/queries.json          ← 쿼리 30개 정의
  search/results/<q-id>.json   ← doc_id 순위 배열
  NORMALIZE.md                 ← 정규화 규칙 (사람이 읽는 SoT)
```

### 6.2 검색 쿼리 30개 선정 규칙
- 실제 vault 내용에서 뽑되, 다음 6종을 각 5개씩:
  1. 순수 명사 (`결제`, `임베딩`)
  2. **조사 결합형** (`결제를`, `모델이`) ← §5.1 핵심 케이스
  3. 영문 기술어 (`RAG`, `Postgres`)
  4. 한영 혼합 (`Obsidian 노트`)
  5. 다어절 구 (`의사결정 트리`)
  6. 결과 0건 예상 쿼리 (음성 검증용)
- 각 쿼리의 현행 결과 `doc_id` **순위 배열**과 **총 건수**를 저장합니다.

### 6.3 정규화 규칙 (`NORMALIZE.md`에 명시)
회귀 비교 전에 다음을 치환합니다. **이 규칙이 없으면 회귀가 매일 깨지고, 아무도 안 보게 됩니다.**
| 대상 | 처리 |
|---|---|
| ISO 타임스탬프 필드(`ts`, `generated_at`, `updated_at`) | `"<TS>"` 로 치환 |
| 상대 날짜 문구(`오늘`, `n일 전`, `확인 대기 N건`) | 숫자만 `<N>` 으로 치환 |
| UUID | 정렬 후 `<UUID-1>`, `<UUID-2>` … 로 안정 치환 |
| 부동소수 | 소수점 2자리 반올림 |
| 배열 순서가 비결정적인 필드 | 키 기준 정렬 후 비교 (어떤 필드인지 명시적으로 열거) |

### 6.4 러너
- `web/tests/regression/run.ts`: 골든 디렉토리를 읽어 새 API를 호출하고 정규화 후 deep-diff.
- 실패 시 **필드 경로 단위로** 차이를 출력해야 합니다(전체 JSON 덤프 금지 — 원인 파악 불가).
- `npm run test:regression -- --scope=read|diet|search|all`

### 6.5 유효기간 — **쓰기 동결로 보장 (§2.3 확정)**

골든은 **P0 시점의 데이터 상태**에 묶여 있습니다. Mac 앱으로 식사 1건만 기록해도 `assistant.today`·`diet.*`·`timeline.list` 골든이 전부 어긋납니다.

| | 내용 |
|---|---|
| 확정 | **P0-4 골든 채취 직후 Mac 앱 쓰기 경로를 코드로 차단**(P0-8). 조회는 자유 |
| 유지 기간 | 최소 P1 게이트 통과까지. **권장은 P4b 완료까지**(P1-5) — 그 전에 풀면 Supabase와 SQLite가 갈라짐 |
| 동결 중 기록 | vault `10 📥 수집함/`에 md로 임시 보관 → P4b 완료 후 웹에서 입력 |
| 검증 | G0-4(동결 실효성) · G1-6(DB 해시 불변) |
| 해제 | P0-8 커밋 revert. 대상 SHA는 `docs/DATA_INVENTORY_2026-07-27.md`에 기록 |

> 골든 재채취는 **최후 수단**입니다. 재채취 시점을 놓치면 회귀 diff가 "코드 문제"인지 "데이터 변동"인지 구분할 수 없게 되고, 그 순간 §9-R4(회귀를 무시하기 시작함)가 현실이 됩니다.

---

## 7. 실측 데이터 인벤토리 (2026-07-27 기준 — P0에서 재확인·동결)

```
SQLite  ~/Knowledge/index/knowledge.db  (약 7MB)
  knowledge_unit     243   (obsidian 224 = vault 217 + Meetings 7 / notes 19)
  knowledge_chunk    621   (unit당 min 1 / max 46 / avg 2.6)
  note_mirror         19   (body_status=ok 전부, body 합계 24,762자)
  source_pointer     243
  connected_source     4   (meeting 1, obsidian 2, notes 1)
  fts_docs           243   ← unit 1:1 (C-6)
  chunk_vector       621   ← 이관 제외 (C-7)
  meeting              0   action_item 0   pipeline_events 0   ← F-1 근거

JSON  ~/Knowledge/services/
  diet/diet.json    meals 25 / workouts 8 / metrics 8 / goals 1 / profile 1
  inbox/inbox.json  items 2 (전부 promoted)

Vault  iCloud .../heejun_pkm/heejun_PKM   md 225 / 총 6.8MB
  비-md: CyberSourceKey_*.pem, postmanv2.html, 90 ⚙️ 첨부파일/*.png|gif
Vault2 ~/Obsidian/Main/Meetings           md 3   ← F-1로 아카이브

Config ~/Knowledge/config/
  app.json  features.json  llm_providers.json  tools_manifest.json
  secrets.json(0600)  mobile_devices.json(0600)  redaction_patterns.json

Tools  ~/Knowledge/tools/  약 4.4GB  ← P7에서 삭제
```

---

## 8. API 메서드 매핑 (유지 47개 / 폐기 15개)

R=읽기(골든 채취 대상) · W=쓰기 · D=폐기

| 메서드 | R/W | Phase | REST 별칭 | 비고 |
|---|---|---|---|---|
| `core.ping` | R | P4a | `GET /api/health` | |
| `core.health` | R | P4a | `GET /api/health?full=1` | 로컬 경로·데몬 필드 제거 |
| `core.services` | R | P4a | — | |
| `assistant.today` | R | P4a | `GET /api/assistant/today` | Hub 단일 호출 |
| `assistant.week_review` | R | P4a | `GET /api/assistant/week` | |
| `assistant.gaps` | R | P4a | `GET /api/assistant/gaps` | |
| `assistant.gaps.evening` | R | P4a | — | |
| `assistant.onboarding.dismissed` | W | P4a | — | `settings` 테이블로 |
| `timeline.list` | R | P4a | `GET /api/timeline` | |
| `knowledge.search` | R | P4a | `GET /api/search?q=` | D-4 방식 적용 |
| `knowledge.health` | R | P4a | — | |
| `corpus.status` | R | P4a | `GET /api/corpus/status` | |
| `corpus.sync` | W | P4a | `POST /api/corpus/sync` | vault Git → DB 재색인 |
| `search.reindex` | W | P4a | `POST /api/search/reindex` | `search_doc` 재구축 |
| `inbox.list` | R | P4a | `GET /api/inbox` | |
| `inbox.create` | W | P4a | `POST /api/inbox` | |
| `inbox.promote` | W | P4a | `POST /api/inbox/:id/promote` | **D-3 상태기계 적용점** |
| `inbox.delete` | W | P4a | `DELETE /api/inbox/:id` | |
| `inbox.json` | R | P4a | — | 디버그 전용으로 축소 |
| `diet.day_summary` | R | P4a | `GET /api/diet/day` | |
| `diet.dashboard` | R | P4a | `GET /api/diet` | |
| `diet.week_review` | R | P4a | `GET /api/diet/week` | |
| `diet.goals` / `.goals.get` | R | P4a | `GET /api/diet/goals` | |
| `diet.profile.get` | R | P4a | `GET /api/diet/profile` | |
| `diet.fasting.status` | R | P4a | `GET /api/diet/fasting` | |
| `diet.ping` | R | P4a | — | |
| `diet.json` | R | P4a | — | 디버그 전용 |
| `diet.log_meal` | W | P4b | `POST /api/diet/meals` | |
| `diet.log_workout` | W | P4b | `POST /api/diet/workouts` | |
| `diet.log_metric` | W | P4b | `POST /api/diet/metrics` | |
| `diet.delete_meal` / `_workout` / `_metric` | W | P4b | `DELETE /api/diet/*/:id` | |
| `diet.goals.set` / `diet.profile.set` | W | P4b | `PUT /api/diet/{goals,profile}` | `settings`에 저장 |
| `diet.suggest` / `.coach` / `.plan` | R | P4b | `GET /api/diet/{suggest,coach,plan}` | 도메인 로직 의존 |
| `diet.estimate_nutrition` | W | P4b→P6 | `POST /api/diet/estimate` | LLM 의존 → P6까지 규칙 fallback |
| `diet.fasting.start` / `.end` / `.preview` | W | P4b | `POST /api/diet/fasting/*` | 리마인더는 `pg_cron` |
| `health.ingest` | W | **P4b**(2026-07-28 정정, 원래 P4a로 오분류) | `POST /api/health/ingest` | **Bearer 토큰 인증**(P3-4). `diet.log_workout`/`diet.log_metric`(아래) 의존 |
| `health.sync_status` | R | P4a | `GET /api/health/sync` | |
| `knowledge.ask` / `.ask.fast` | R | **P6** | `POST /api/ask` | 생성 경로 |
| `meeting.*` (13개) | **D** | — | — | F-1 |
| `knowledge.review.get/list/accept` | **D** | — | — | F-1 |
| `knowledge.meetings` | **D** | — | — | F-1 |
| `knowledge.systemaudio.write` | **D** | — | — | F-1 |
| `knowledge.gateway.accept` · `pair/*` | **D** | — | — | 페어링 폐기 |
| `knowledge.db` · `knowledge.cleartext.http` | **D** | — | — | 로컬 전용 |

---

## 9. 리스크 · 중단 기준

| # | 신호 | 즉시 조치 | 중단 기준 |
|---|---|---|---|
| R1 | P0-9 정책 체크에서 `pg_cron`/`pg_trgm` 활성 불가 | 오너 보고 | **P1 진입 중단** — 스택 재검토 필요 |
| R2 | P1 검색 recall이 현행보다 낮음 | `to_tsvector('simple')` 설정·정규화 점검 → `hybrid` 모드로 보강 | 3회 시도 후 미달 시 오너 보고. **trgm 튜닝으로 P1을 늘리지 말 것**(D-4) |
| R3 | G3-3에서 anon 키로 데이터가 나옴 | **즉시 배포 중단** | RLS 전면 통과 전 어떤 배포도 금지 |
| R4 | 골든 diff가 상시 발생해 무시하기 시작함 | §6.3 정규화 규칙 보강. **먼저 쓰기 동결이 실제로 유지되고 있는지 확인**(G1-6) | 회귀를 끄는 선택은 금지 — 그 순간 안전망 0 |
| R4b | 동결 기간에 Mac 앱으로 기록해버림 | G0-4/G1-6에서 즉시 검출됨 → 골든 재채취 후 그 사실을 인벤토리에 기록 | 재채취 없이 진행 금지 |
| R5 | Supabase 무활동 정지 발생 | keep-alive 동작 확인, 복구 절차 문서화 | — |
| R6 | free LLM 쿼터 소진 | extractive fallback 동작 확인 (G6-3) | fallback이 안 되면 P6 미완료 |
| R7 | Phase가 부풀어 3세션 이상 소요 | 범위를 문서에 적힌 게이트로 강제 축소 | 스코프 추가는 `REFACTOR_BACKLOG.md`로 |
| R8 | Mac 앱과 웹을 둘 다 고치고 있음 | 즉시 중단, P5 완주 우선 | D-5 종료일 준수 |
| R9 | 마이그레이션 중 데이터 손상 의심 | 읽기전용 백업에서 재시작 | — |

---

## 10. 한 줄 요약

> **P0에서 기준선을 만들지 못하면 나머지 전부가 감(感)으로 진행됩니다.**
> 기존 시나리오는 미팅 폐기와 함께 소멸하므로(C-1), **골든 스냅샷이 유일한 합격선**이며 **쓰기 동결이 그 유효성을 지킵니다**(§2.3).
> 순서는 고정입니다: **기준선(P0) → 데이터(P1·P2) → 인증(P3) → API(P4) → UI(P5) → 생성(P6) → 해체(P7).**
> 완료 정의는 하나뿐입니다: **Mac을 꺼도 동작한다.**

---

## 부록 A. 결정 이력

| 일자 | 결정 | 방식 |
|---|---|---|
| 2026-07-27 | F-1~F-6 (미팅 폐기 · vault Git · Supabase · Next.js · 프라이버시 하향 · 기능 동결) | 방향성 문서 §7, 오너 승인 |
| 2026-07-27 | C-1~C-8 정정 사항 확정 | 코드·DB·vault 실측 |
| 2026-07-27 | D-1 모노레포 `web/` | 스코어링 8.70 vs 7.25 → 오너 선택 |
| 2026-07-27 | D-2 vault 레포 분리 | 기술적 강제(Obsidian Git) |
| 2026-07-27 | D-2b 백업 = 별도 `knowledge-backup` 레포 | 스코어링 8.90 vs 8.30 vs 7.40 → 방향성 §5.2.3 원안 번복 |
| 2026-07-27 | D-3 상태기계 2곳 이식 | 스코어링 8.25 vs 8.10 vs 6.90 → 오너 선택 |
| 2026-07-27 | D-4 게이트 동등 + trgm 플래그 대기 | 스코어링 8.60 vs 8.40 vs 7.65 → 오너 선택 |
| 2026-07-27 | D-5 병행 종료 = P5 + 7일 | 기본값 유지 |
| 2026-07-27 | 골든 유효성 = P0 후 쓰기 동결 | 스코어링 8.80 vs 7.90 vs 5.20 → 오너 선택 |

> 이후 결정이 추가·번복되면 이 표에 한 줄씩 append 합니다. **본문을 조용히 고치지 마세요.**
