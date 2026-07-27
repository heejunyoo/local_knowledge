# Knowledge 리팩토링 방향성 — Mac 서버 → Vercel 웹 + 무료 클라우드 저장소

| Field | Value |
|-------|--------|
| Date | 2026-07-27 |
| Status | **Direction (방향성)** — phase별 액션 플랜은 별도 세션 |
| 목표 | ① 데이터: 무료 클라우드 저장소 ② 제공: native app → Vercel 웹 |
| 실행 | 별도 세션 · Sonnet |

---

## 1. 현황 진단 (측정된 사실)

### 1.1 코드 규모
| 영역 | LOC(테스트 포함) | 성격 |
|------|------------------|------|
| KnowledgeUI (macOS SwiftUI) | 6,328 | **버려짐** (웹 재작성) |
| KnowledgeWorkers | 5,707 | 절반은 로컬 모델 호출 shim |
| KnowledgeCore | 4,446 | 도메인 규칙 — **가치 있는 부분** |
| KnowledgeIndex (SQLite) | 1,685 | 스키마는 이식, 코드는 재작성 |
| KnowledgeGateway (HTTP) | 1,341 | Next.js route handler로 대체 |
| KnowledgeRPC (UDS) | 1,280 | **전면 삭제** (프로세스 분리 자체가 사라짐) |
| KnowledgeCapture | 1,230 | **브라우저에서 불가** |
| Apps/KnowledgeMobile (iOS) | ~14 파일 | **버려짐** |

### 1.2 실제 데이터 (핵심 발견)
```
~/Knowledge  총 4.4GB
  └ tools/     4.4GB   ← whisper large-v3-turbo + Qwen2.5-7B-Q4 모델 바이너리
  └ index/     7MB     ← SQLite (knowledge_unit 243, chunk 621, note_mirror 19)
  └ services/  12KB    ← diet.json (meals 25, workouts 8, metrics 8), inbox.json
  └ audio/ transcripts/ summaries/  0B
iCloud vault: 마크다운 225개  ← 실질 지식 자산 (git 미관리)
```
DB `meeting` 테이블 = **0행**. `pipeline_events` = **0행**.

> **결론: 이 프로젝트는 "데이터가 무거워서" 서버가 필요한 게 아니라, "로컬 모델을 돌리려고" PC가 서버가 된 것이다.**
> 유효 사용자 데이터는 수십 MB 수준이며 어떤 무료 티어에도 들어간다.
> 그리고 녹음 파이프라인(설계 문서 분량의 절반, 코드의 30%)은 **실사용 0건**이다.

### 1.3 이미 클라우드 이관이 끝난 것
- `cloud_llm: true`, `LLMProviderCatalog` (Groq → Gemini → OpenRouter 캐스케이드) + `LLMAnswerCache` + throttle 이미 구현·검증됨.
- 즉 **가장 어려운 부분(생성 경로의 클라우드화)은 이미 완료 상태**다. 남은 건 저장소와 전달 경로.

---

## 2. 방향 한 줄

> **"항상 켜둔 Mac"을 아키텍처에서 제거한다. Mac은 서버가 아니라 (선택적) 클라이언트 하나가 된다.**
> Vercel = 단일 표면 · 무료 관리형 저장소 = SoT · 모델 = free-tier API · 캡처 = 브라우저/Shortcuts.

### 2.1 차별축 재정의 (불편하지만 필수)
기존 문서(`FORWARD_DIRECTION_RESEARCH_2026-07.md`)가 선언한 해자는 **"local-first 데이터 주권 × (지식×몸) 교차"** 였다.
클라우드로 가면 **앞의 절반은 사라진다.** 이걸 인정하지 않으면 리팩토링 내내 자기모순이 생긴다.

| 항목 | Before | After (권고) |
|------|--------|--------------|
| 해자 | 로컬 주권 + 교차 | **교차(지식×몸×하루) + 어디서나 · 설치 0** |
| 프라이버시 주장 | "내 Mac을 절대 안 떠남" | **"내 계정 · 단일 테넌트 · redaction preflight 유지"** (정직하게 하향) |
| 가용성 | Mac이 깨어 있을 때 | **항상** ← 실질적으로 가장 큰 사용성 개선 |
| 도달성 | Tailscale + 7일 재서명 iOS 앱 | **URL 하나** ← 두 번째로 큰 개선 |

로컬 주권을 포기하는 대가로 얻는 것: **재서명 지옥 · TCC 권한 · 4.4GB 모델 · LaunchAgent · UDS · 페어링 코드 · 데몬 supervisor가 전부 소멸.** 유지비가 한 자릿수로 떨어진다. 1인 제품에서 이 교환은 남는 장사다.

---

## 3. 능력 이관 매트릭스 (MECE)

### A. 그대로 옮겨짐 (가치의 대부분)
| 기능 | Job | 비고 |
|------|-----|------|
| Hub / 오늘 (`assistant.today`) | J1 | 순수 조회·집계 |
| 지식 검색 (FTS5) | J3 | libSQL이면 FTS5 그대로 |
| Chat / RAG | J3 J5 | 이미 cloud LLM |
| Diet · IF · 체중 로깅 | J4 | JSON → DB 테이블화 |
| Inbox 캡처 → 승격 | J6 | 웹이 오히려 유리 |
| Timeline · 주간 리뷰 · gaps | J5 J8 | 순수 로직 |
| 액션 아이템 | J2 | |

### B. 메커니즘 교체 필요
| 기능 | Before | After |
|------|--------|-------|
| ASR | whisper.cpp 로컬 (2.9GB) | **Groq Whisper API** (이미 카탈로그에 있는 provider) |
| 요약 LLM | llama.cpp Qwen 7B (1.5GB) | **free-tier 캐스케이드 단독** (fallback = extractive 유지) |
| 파이프라인 tick | 데몬 폴링 루프 | **요청 트리거 + 큐** (Vercel은 상주 프로세스 없음) |
| 임베딩/벡터 | `LocalHashEmbedder` (해시 기반=사실상 비의미적) | **초기엔 끈다.** 243 unit 규모에서 FTS5로 충분. 나중에 free 임베딩 API |
| 인증 | 6자리 페어링 코드 (Tailscale 신뢰망) | **공개 인터넷 = 실인증 필수** (단일 사용자 OAuth 또는 passkey) — **전례 0건, 신규 구축** (§6.5.2) |
| 런타임 설정 | `config/features.json` · `app.json` **파일** | **DB Settings 키-값 테이블 + 캐시** (§6.5.4 P-1) |
| 비밀정보 | `config/secrets.json` 파일 | **Vercel 환경변수** (§6.5.4 P-2) |
| Vault SoT | iCloud Drive 마크다운 | **Git 레포 또는 DB** ← §7 결정 항목 |
| HealthKit | iOS 네이티브 read | **Apple Shortcuts 자동화 → API POST** (무료·설치 0) |
| 알림 | iOS LocalNotify | **Web Push (설치형 PWA)** — 정확도 하향 감수 |

### C. 구조적으로 불가 → 포기 대상
| 기능 | 이유 |
|------|------|
| **시스템 오디오 캡처 (ScreenCaptureKit)** | 브라우저에 동등 기능 없음. `getDisplayMedia` 탭 오디오는 Chrome 한정·부분적 |
| Apple Notes 대량 임포트 (AppleScript) | Mac 전용 → **1회성 수출**로 대체 |
| 메뉴바 상주 UX | 웹에 없음 |
| 실기기 HealthKit 직접 read | B의 Shortcuts로 대체 |

---

## 4. 타깃 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│  브라우저 (데스크톱/모바일 동일, PWA 설치 가능)              │
│  Next.js App Router · 단일 표면 · 설치·서명·재서명 없음      │
└───────────────┬─────────────────────────────────────────────┘
                │ HTTPS (Auth: 단일 사용자)
┌───────────────▼─────────────────────────────────────────────┐
│  Vercel                                                      │
│   Route Handlers  ← 기존 core.* / diet.* / inbox.* API 계승  │
│   Server Actions  ← 뮤테이션                                 │
│   Cron (제한적)   ← 일 단위 배치만                           │
└───┬──────────────┬──────────────┬───────────────────────────┘
    │              │              │
┌───▼────┐  ┌──────▼──────┐  ┌───▼──────────┐
│ 관리형  │  │ 오브젝트     │  │ free-tier    │
│ DB+FTS │  │ 스토리지     │  │ LLM / STT    │
│ (SoT)  │  │ (오디오/첨부)│  │ (Groq 등)    │
└────────┘  └─────────────┘  └──────────────┘
    ▲
    │ (선택) Apple Shortcuts → POST /api/health/ingest
    │ (선택) Obsidian ↔ Git 동기 (vault SoT 유지 시)
```

**사라지는 것:** LaunchAgent · `knowledged` · UDS 소켓 · Tailscale 의존 · 페어링 스토어 · DaemonSupervisor · 코드사이닝 · TCC · tools_manifest/sha256 검증 · 4.4GB 모델.

### 4.1 Vercel 제약이 설계를 바꾸는 지점 (중요)
1. **상주 프로세스 없음** → "recorded → ASR → transcribed" 자동 tick 루프 폐기. 상태 전이는 **요청/큐 이벤트**로만.
2. **함수 실행시간 상한** → 긴 ASR·요약을 한 함수에서 못 끝냄. → 외부 큐(예: QStash류)로 단계 분해, 또는 STT를 **브라우저 → STT API 직접 호출**로 우회.
3. **파일시스템 비영속** → `~/Knowledge` 트리 개념 자체가 소멸. `KnowledgePaths` 삭제.
4. **Hobby cron 빈도 제한** → 단식 리마인더 같은 분 단위 스케줄은 cron으로 불가. 외부 스케줄러 또는 클라이언트측 계산.
5. **크래시 복구가 더 중요해짐** → 기존 `PipelineGraph` default-deny + R1–R6 복구 규칙은 **버릴 게 아니라 오히려 핵심 자산**이다. 서버리스는 함수가 작업 중간에 죽는 게 정상이기 때문.

---

## 5. 스택 권고

| 레이어 | 1순위 권고 | 근거 | 대안 |
|--------|-----------|------|------|
| 앱/호스팅 | Next.js (App Router) + TypeScript on Vercel | 사용자 요구사항 확정 | — |
| **DB · 인증 · 스케줄** | **Supabase Free (Postgres)** ✅확정 | DB+Auth+RLS+pg_cron+pgvector를 **한 무료 티어로 묶음**. 한국어 FTS 손실 없음(§5.1) | Neon(Postgres 표준이라 이전 가능) |
| ~~오브젝트~~ | **불필요** | §7-1(녹음 폐기)로 오디오·첨부 blob 소멸 | Supabase Storage가 이미 포함 |
| LLM | Groq 우선 캐스케이드 (기존 카탈로그 재사용) | 이미 구현·검증. STT는 §7-1로 불필요 | Gemini/OpenRouter |
| 인증 | **Supabase Auth + RLS** | 전례 0건인 최대 리스크(§6.5.2)를 **관리형으로 하향** (§5.2.2) | — |
| Vault | Git 프라이빗 레포 (Obsidian Git 플러그인 동기) ✅확정 | 마크다운 SoT 원칙 보존 + 무료 | — |

> ⚠️ **무료 티어 수치(용량·RPD·유휴 정지 정책)는 자주 바뀐다.** 이 문서는 수치를 확정하지 않는다.
> phase 플랜 세션에서 **당일 기준으로 재확인**할 것. 특히 "일정 기간 미사용 시 DB 정지" 정책은 산발적으로 쓰는 개인 앱에 치명적이므로 선택 기준에 반드시 포함.

### 5.1 ~~Postgres보다 libSQL을 먼저 권하는 이유~~ → **철회 (2026-07-27 실측)**

당초 "Postgres로 가면 한국어 형태소 문제가 새로 생긴다"고 판단했으나 **측정 결과 근거가 성립하지 않는다.**

현재 FTS는 `tokenize = 'unicode61'` (기본값) — **형태소 분석이 전혀 없다.** 실제 인덱스 토큰:
```
가능성이 · 아이템의 · 요청을 · 방식이라 · 대해서 · 스타트업이   ← 조사가 붙은 어절 그대로
```
실측 쿼리:
```
MATCH '결제'   → 32건
MATCH '결제를' →  3건     ← 완전히 별개 토큰
```
즉 **"결제"로 검색하면 "결제를/결제가/결제는"이 걸리지 않는다.** 현재 baseline은 조사 포함 어절 exact match이며 품질이 매우 낮다.

| | 한국어 처리 | 현 baseline 대비 |
|---|---|---|
| SQLite FTS5 `unicode61` (현행) | 어절 exact, 조사 미분리 | 기준 |
| Postgres `to_tsvector('simple')` | 어절 exact, 조사 미분리 | **동등** |
| Postgres **`pg_trgm`** (Supabase 기본 지원) | 트라이그램 부분일치 → 조사 변형 흡수 | **개선** |

→ **libSQL의 "이식 리스크 최소" 근거가 사라졌다.** 또한 `fts_docs`는 external-content 테이블이 아니라 **독립 FTS5 테이블**이어서(실측 DDL 확인) 어느 쪽으로든 이식 난이도가 낮다.
→ §7-3 결정을 **Supabase(Postgres)로 전환**한다. 근거는 §5.2.

---

### 5.2 Supabase 무료 티어 커버리지 (전면 무료 운영 전제)

오너 제약: **개발·운영 전 구간 무료 티어.** 이 관점에서 Supabase는 단순한 DB가 아니라 **여러 레이어를 한 번에 닫는다.**

#### 5.2.1 커버 매트릭스

| 필요 레이어 | Supabase 무료로 커버 | 이 프로젝트 실수요 | 판정 |
|---|---|---|---|
| **DB (SoT)** | Postgres | 실데이터 **7MB** (unit 243 / chunk 621 / diet / inbox) | ✅ 압도적 여유 |
| **인증** ★ | **Supabase Auth** (매직링크 / OAuth) + **RLS** 행 단위 격리 | 사용자 **1명** | ✅ **최대 수확 — §6.5.2 리스크를 관리형으로 해소** |
| 전문검색 | `to_tsvector('simple')` + **`pg_trgm`** | md 225 + unit 243 | ✅ 현행 동등~개선 (§5.1) |
| 벡터 | `pgvector` | 초기 비활성(§3-B) | ✅ 켤 때 추가 비용 0 |
| 파일 | Storage | §7-1로 오디오 폐기 → **거의 미사용** | ✅ |
| **스케줄** ★ | **`pg_cron`** | 단식 리마인더 등 | ✅ **Vercel Hobby cron "일 1회" 제약을 우회** (§4.1-4 해소) |
| 서버 로직 | Edge Functions | Vercel 라우트로 충분 | ○ 예비 |
| 외부 호출 | `pg_net` | cron에서 LLM/푸시 트리거 | ○ 예비 |
| 실시간 | Realtime | 1인 앱 → 불필요 | — |

> ⚠️ **용량 수치는 이 문서에 확정하지 않는다.** 무료 티어는 자주 바뀐다(§5 주석 동일 원칙).
> 다만 **실데이터가 7MB 규모**라 어떤 세대의 무료 한도든 **용량은 병목이 아니다.** P0에서 확인할 것은 용량이 아니라 **정책**(아래 5.2.3).

#### 5.2.2 Supabase 채택 시 결정적 이점 2가지

1. **인증이 "신규 구축"에서 "설정"으로 내려간다** — §6.5.2에서 확인했듯 오너에겐 공개 인터넷 인증 전례가 **0건**이다. 직접 짜면 세션·토큰 만료·CSRF·비밀번호 저장을 전부 새로 배워야 하고, 이 프로젝트에서 **가장 실패 확률이 높은 단계**다. Supabase Auth + RLS는 이걸 관리형으로 대체하고, **RLS는 "코드 실수로 인증을 우회하는" 사고를 DB 레이어에서 막는다.** libSQL/Turso는 DB만 주므로 인증을 여전히 직접 지어야 한다.
2. **`pg_cron`이 Vercel Hobby의 스케줄 제약을 무력화한다** — §4.1-4에서 "분 단위 스케줄 불가"를 제약으로 적었는데, DB 레이어에 cron이 있으면 해결된다. 외부 유료 큐(QStash 등)가 필요 없어진다.

#### 5.2.3 Supabase 무료의 실질 리스크 (용량 아님)

| 리스크 | 내용 | 완화 |
|---|---|---|
| **무활동 시 프로젝트 일시정지** ★ | 일정 기간(내 지식 기준 약 7일) 요청이 없으면 프로젝트가 정지되고 **수동 복구**가 필요 | ① 매일 쓰는 개인비서라면 자연히 회피 ② **Vercel Cron(일 1회) 또는 무료 uptime 핑으로 keep-alive** ③ 장기 여행 시 정지 가능성을 UX로 수용 |
| **자동 백업 없음** | 무료 티어는 PITR·일일 백업 미제공 | **`pg_dump` → GitHub Actions 주기 실행(무료)** → §7-2의 Git 레포가 vault뿐 아니라 **DB 덤프 보관소** 역할까지 겸함 |
| 무료 정책 변경 | 티어 조건은 바뀐다 | 스키마를 표준 Postgres로 유지 → Neon 등으로 이전 가능성 확보. **Supabase 전용 기능은 Auth·Storage로 한정** |

> **P0 검증 항목(용량 아님):** ① 정지 정책의 정확한 기준일과 복구 방식 ② keep-alive가 정지 회피에 실제로 유효한지 ③ `pg_cron`·`pg_trgm`·`pgvector`가 현재 무료 티어에서 활성화 가능한지.

#### 5.2.4 전체 스택이 무료로 닫히는가 — **닫힌다**

| 레이어 | 서비스 | 무료 근거 |
|---|---|---|
| 호스팅·CDN·도메인 | **Vercel Hobby** (`*.vercel.app`) | 비상업 개인 사용 |
| DB · 인증 · 스토리지 · 스케줄 | **Supabase Free** | §5.2.1 |
| Vault SoT · DB 덤프 백업 | **GitHub 프라이빗 레포 + Actions** | §7-2 |
| LLM 생성 | **Groq 무료 캐스케이드** (+Gemini/OpenRouter 예비) | 기존 `LLMProviderCatalog` 재사용 |
| 최종 fallback | **extractive 요약** (외부 의존 0) | 이미 구현됨 |

**유료 요소 0개.** 그리고 어느 하나가 무료 정책을 바꿔도 대체재가 있다 — LLM은 provider 카탈로그로 교체, DB는 표준 Postgres라 이전 가능, vault는 Git이라 종속 없음.

---

## 6. 리라이트의 성격 — "코드 이식이 아니라 스펙 이식"

Swift 22k LOC 중 Vercel에서 재사용 가능한 코드는 **0**이다. 그러나 자산은 코드가 아니다:

| 이식 대상 자산 | 위치 | 왜 가치 있나 |
|---------------|------|-------------|
| JSON Schema | `Schemas/meeting-summary-v1.json` | 계약 그대로 |
| **드리프트 시나리오** | `evals/scenarios/*.json` (S02, S02b, S05, S06, S11, S12) | **TS 재작성을 동일 기준으로 검증** — 리라이트 안전망의 핵심 |
| 정책 문서 | `docs/thresholds.md`, `privacy_rules.md`, `commit_protocol.md`, `memory_curation.md` | 임계값·규칙의 SoT |
| redaction 패턴 | `docs/redaction_patterns.json`, `redaction_allowlist.json` | 데이터 파일 → 그대로 |
| 순수 도메인 로직 | `DietNutritionCalc`(257) `DietPresets`(71) `PipelineGraph`(161) `Thresholds`(148) `TextChunker`(156) | ~800 LOC, TS 1:1 번역 + 기존 테스트 이식 가능 |
| DB DDL | `KnowledgeIndex/Schema.swift` | libSQL 선택 시 거의 그대로 |
| API 형태 | `core.* / assistant.* / diet.* / inbox.* / timeline.*` | **REST 매핑 시 그대로 유지 → UI 재작성 범위 축소** |

**전략:** "포팅 프로젝트"로 부르지 말고 **"스펙 기반 재구현 + 시나리오 회귀"** 로 프레이밍한다. Sonnet 실행에 특히 유리하다 — 시나리오 JSON이 합격 기준을 기계적으로 정의해 주기 때문.

---

## 6.5 선행 프로젝트 자산 조사 (2026-07-27 실측)

리팩토링 전, 이 머신의 기존 프로젝트에서 **저장소·로그인을 실제로 어떻게 구현했는지** 조사했다.

### 6.5.1 조사 대상
| 프로젝트 | 위치 | 성격 | 최종 커밋 |
|---------|------|------|----------|
| **decade_journey** | `~/Documents/pythonvenv/decade_journey` | FastAPI 가족 사진·타임라인 앱 (RAG·얼굴인식·AI 인터뷰) | 2026-01 |
| pyweb | `~/Documents/pythonvenv/pyweb` | FastAPI CyberSource 결제 데모 | — |
| cybs-so-demo | `~/IdeaProjects/cybs-so-demo` | Maven 단일 `Main.java` 16줄 | — |

`~/IdeaProjects` 안에는 KnowledgeApp 외에 `cybs-so-demo`(16줄 데모)뿐이며 참고할 게 없다.
**실질 선행 사례는 `decade_journey` 하나**다.

### 6.5.2 결론 ① — **재사용할 인증 구현이 없다** ★

| 프로젝트 | "로그인"의 실체 | 공개 인터넷 사용 가능? |
|---------|----------------|---------------------|
| decade_journey | `routers/auth.py` **25줄**. 쿠키(`decade_journey_profile`)에 **이름 문자열만** 저장(httponly, 1년). 비밀번호·토큰·검증 **전무**. `/set-profile/{name}` 은 아무 이름이나 받는다 | ❌ 인증이 아니라 **가족 구성원 구분용 프로필 선택기** |
| KnowledgeApp | 6자리 페어링 코드 → Bearer 토큰. 단 `pair/start`는 **loopback only**, **Tailscale 신뢰망 전제** | ❌ 신뢰망이 사라지면 모델 자체가 성립 안 함 |
| pyweb | JWT 문자열이 나오지만 **CyberSource 결제 transient token** 파싱. 사용자 인증 아님 | ❌ 무관 |

> **공개 인터넷 대상의 실제 인증은 이 머신에 전례가 0건이다.**
> 지금까지 모든 프로젝트는 "신뢰된 네트워크 안 / 집 안의 기기"를 전제해 인증을 **의도적으로 생략**해 왔다.
> Vercel로 나가는 순간 이 전제가 붕괴하므로, 인증은 **이식이 아니라 신규 구축**이며 P3에서 별도 학습·검증 시간을 잡아야 한다.
> 절대 하지 말 것: decade_journey의 쿠키 프로필 패턴을 공개 URL에 그대로 가져오는 것 — 그건 **URL을 아는 사람 누구나 전체 데이터에 접근**하는 것과 같다.

### 6.5.3 결론 ② — **저장소도 전례가 전부 "로컬 파일"**

`decade_journey/database.py`: `SQLALCHEMY_DATABASE_URL = "sqlite:///./decade_journey.db"`
`docker-compose.yml` 볼륨 6개: DB 파일 · `static/uploads` · `lancedb_data` · `backups` · HuggingFace 캐시 · 호스트 Ollama 연결.

| | decade_journey | KnowledgeApp | Vercel에서 |
|---|---|---|---|
| DB | 로컬 SQLite 파일 4.2MB | 로컬 SQLite 7MB | ❌ 파일시스템 비영속 |
| 업로드 | `static/uploads` 로컬 디스크 | `~/Knowledge/audio` | ❌ |
| 벡터 | LanceDB 로컬 디렉토리 (+chroma_db 잔재) | `chunk_vector` 테이블 | ❌ / △ |
| 모델 | HuggingFace 캐시 + 호스트 Ollama | whisper+llama 4.4GB | ❌ |
| 워커 | **Huey consumer 서브프로세스** (main.py lifespan에서 기동) | **knowledged 데몬 tick** | ❌ 상주 프로세스 없음 |

> **두 프로젝트가 독립적으로 완전히 같은 패턴("Mac이 서버")에 도달했다.**
> 즉 이번 리팩토링은 **오너의 첫 클라우드 전환**이며 사내 전례가 없다. 이건 리스크 신호다 — P0에 "무료 티어 실측"뿐 아니라 **학습·시행착오 시간**을 명시적으로 넣어야 한다.
> 그리고 `decade_journey`를 "잘 돌아가니 이렇게 하자"고 참고하면 **위 5줄이 전부 Vercel에서 무너진다.** 참고는 도메인 로직 한정.

### 6.5.4 결론 ③ — 그래도 이식할 가치가 있는 패턴 4개

| # | 패턴 | 출처 | 왜 이번에 쓰나 |
|---|------|------|---------------|
| **P-1** | **Settings 키-값 테이블 + 메모리 캐시 싱글턴** | `models.Settings`(key/value/updated_at) + `services/config.py` (`ConfigService`, DB→캐시 로드) | **가장 값어치 있는 발견.** KnowledgeApp은 설정이 `config/features.json`·`app.json` **파일** 기반인데 Vercel엔 파일이 없다. → **features.json / app.json 을 DB Settings 테이블로 옮기는 게 정답이며, 그 구현 전례가 이미 있다** |
| **P-2** | **비밀정보 = 환경변수(.env)** | `decade_journey/.env` (`GEMINI_API_KEY`) + `load_dotenv()` | KnowledgeApp은 `config/secrets.json` **파일**. Vercel 환경변수로 통일해야 하는데 decade_journey 쪽이 **이미 정합**하므로 그 방식을 채택 |
| **P-3** | **AI provider 스위치 + fallback 보장** | `services/ai_service.py` (`config.get("ai_provider")` 분기, 실패 시 `_get_fallback_question()`) | KnowledgeApp `LLMRouter`(→extractive fallback)와 **동일 사상에 독립적으로 도달**. 이 패턴은 사실상 검증 완료 → 그대로 유지 |
| **P-4** | Gemini 무료 임베딩 실사용 경험 | `services/rag.py` — `text-embedding-004` 768차원, **local/gemini 이중 인덱싱** 테이블 운영 | §3-B에서 벡터를 초기 비활성하기로 했으나, 나중에 켤 때 `LocalHashEmbedder`를 대체할 **검증된 무료 경로**가 이미 있다 |

부수 확인: **Groq는 두 프로젝트 모두에서 이미 사용 중**(`decade_journey/services/groq.py`, KnowledgeApp `LLMProviderCatalog` order 1순위) → §5 LLM 선택의 근거가 한 단계 강해진다.

---

## 7. 확정 결정 (2026-07-27, 오너 승인)

### 7-1. 미팅 녹음 파이프라인 → **전면 폐기** ✅
브라우저는 시스템 오디오를 캡처할 수 없고, `meeting` 테이블은 0행(실사용 0)이다.
**폐기 대상:** `KnowledgeCapture` 패키지 전체 · `WhisperASR` · `AppleSpeechASR` · `KnowledgeAudioHelper` · `SystemAudioRecorder`/`MicRecorder`/`MonoWavWriter` · `MeetingArtifactReader` · `TranscriptCoalesce` · `Stage2Evidence` · `SummaryCritic` · `VaultCommit`(미팅 경로) · `meeting.*` RPC 전체 · `audio/ transcripts/ summaries/` 트리 · whisper 모델 2.9GB · TCC(화면 기록·음성 인식) 요구 전체.

**파급 효과 (플랜에 반영할 것):**
- **오브젝트 스토리지가 불필요해진다** → §5 스택에서 R2/Blob 레이어 삭제. 저장소는 DB 하나.
- **큐/장시간 작업이 불필요해진다** → §4.1-2(함수 실행시간 상한)가 사실상 무력화. Vercel 제약 중 가장 까다로운 항목이 사라짐.
- **STT 의존이 사라진다** → free-tier 의존이 LLM 하나로 축소.
- `Schemas/meeting-summary-v1.json` 및 미팅 관련 시나리오는 **아카이브**(삭제 말고 보존).
- 단, `PipelineGraph`의 default-deny + R1–R6 복구 규칙은 **미팅과 무관하게 유지**한다 (§4.1-5 근거).

> ⚠️ 이 결정으로 제품 정체성이 "미팅 메모리 + 개인비서" → **"지식 vault × 몸 × 하루 개인비서"** 로 좁혀진다.
> `README.md`·`core_platform_sketch.md`·`FORWARD_DIRECTION_RESEARCH_2026-07.md`의 J2 관련 서술은 P0에서 정합화 필요.

### 7-2. Vault SoT → **Git 프라이빗 레포** ✅
iCloud Drive의 md 225개를 Git 프라이빗 레포로 이전하고 Obsidian Git 플러그인으로 동기한다.
마크다운 SoT 원칙과 Obsidian 편집 루프를 보존한다.
**플랜에서 다뤄야 할 것:** 커밋 충돌 처리 · 웹에서 편집 시 커밋 주체·경로 규약 · 기존 `commit_protocol.md` 재해석 · 첨부파일(`90 ⚙️ 첨부파일`, .pem 등) 취급 · **레포에 올리기 전 비밀정보 스캔**(현재 vault에 `CyberSourceKey_*.pem` 존재 확인됨).

### 7-3. DB → ~~libSQL/SQLite 호환~~ → **Supabase (Postgres)** ✅ *2026-07-27 번복*

**최초 결정은 libSQL이었으나 같은 날 두 가지 새 근거로 번복한다.**

| 번복 근거 | 내용 |
|---|---|
| ① FTS 실측 (§5.1) | 현행이 `unicode61` 어절 exact match라 **Postgres가 동등, `pg_trgm`은 개선**. libSQL의 유일한 우위였던 "이식 리스크 최소"가 소멸 |
| ② 전면 무료 티어 제약 + 인증 전례 0건 (§6.5.2) | Supabase는 **DB+Auth+RLS+Storage+pg_cron을 한 무료 티어로** 묶는다. libSQL은 DB만 주므로 **가장 실패 확률 높은 인증을 여전히 직접 지어야** 한다 |

부수 효과: `pg_cron`이 §4.1-4(Vercel Hobby 스케줄 제약)를 해소하고, `pgvector`로 §3-B의 벡터 재활성 경로도 추가 비용 0으로 확보된다.
**단, 무료 티어의 "무활동 시 정지" 정책은 P0에서 실측 확인**(§5.2.3 · §9).

### 7-4. 프라이버시 포지션 (묵시적 수용)
위 결정을 진행하는 이상 "내 Mac을 절대 안 떠남" 주장은 성립하지 않는다.
§2.1대로 해자를 **교차(지식×몸×하루) + 가용성 + 도달성**으로 재고정하고, 프라이버시는 "내 계정 · 단일 테넌트 · redaction preflight 유지"로 **정직하게 하향 표기**한다.

---

## 8. Phase 골격 (뼈대만 — 상세는 별도 세션)

§7 확정 반영 — 오디오/STT/오브젝트 스토리지/큐가 전부 빠져 골격이 한 단계 가벼워졌다.

```
P0  스코프 동결: 미팅 파이프 아카이브 + 문서 정합화 (README·core_platform_sketch)
    Supabase 무료 **정책** 실측 (정지 기준·pg_cron/pg_trgm/pgvector 활성 여부) — 용량 아님(§5.2.3)
    데이터 인벤토리 동결 + 읽기전용 백업 · vault 비밀정보 스캔 (.pem 등) ← Git 이전 전 필수
    ★ 클라우드 전환 전례가 0건이므로(§6.5.3) 실측·학습 시간을 명시적으로 배정
P1  스키마 이식 (SQLite DDL → Postgres) + 실데이터 마이그레이션
      대상: knowledge_unit 243 / chunk 621 / note_mirror 19 / diet.json / inbox.json
      + features.json·app.json → Settings 키-값 테이블 (§6.5.4 P-1 패턴)
      FTS: `to_tsvector('simple')` 또는 `pg_trgm` — 어느 쪽이 나은지 실측 비교
      → 게이트: 검색 결과가 현행(FTS5 unicode61) **이상**. §5.1 실측치를 기준선으로 사용
P2  vault 225 md → Git 프라이빗 레포 + Obsidian Git 동기 + **pg_dump 백업 Actions**(§5.2.3)
      → 게이트: 웹↔Obsidian 양방향 편집이 충돌 없이 왕복
P3  ★ 인증 = **Supabase Auth + RLS 설정** (직접 구현 아님, §5.2.2)
      → 게이트: RLS로 미인증 요청이 **DB 레이어에서** 차단됨 (URL 노출만으로는 접근 불가)
P4  API 계층 (core.*/assistant.*/diet.*/inbox.*/timeline.* 메서드명 보존) + 시크릿을 환경변수로
      → 게이트: 시나리오 JSON 회귀 통과
P5  웹 UI (Hub·검색·Chat·Diet·Inbox) — 기존 뷰 구조 참조, Toss 디자인 계승, PWA
      → 게이트: URL만으로 폰·데스크톱 동작
P6  생성 경로 이식 (LLM 캐스케이드 + LLMAnswerCache + throttle + extractive fallback)
      참고: `ai_service.py` provider 스위치 + fallback 패턴 (§6.5.4 P-3)
P7  레거시 해체 (LaunchAgent 제거, 4.4GB tools 삭제, Mac/iOS 앱 아카이브)
      → 게이트: Mac을 꺼도 서비스 정상
```
**마지막 게이트가 이 리팩토링의 진짜 완료 정의: "Mac 전원을 내려도 서비스가 동작한다."**

> 리팩토링 기간 = **기능 동결**. `FORWARD_DIRECTION_RESEARCH_2026-07.md`의 F-S/F-M 백로그는 P6 이후에 재평가한다
> (단 J2 관련 항목 F-S1·F-S2·F-S3·F-S4는 7-1 결정으로 **소멸**).

---

## 9. 리스크 (pre-mortem)

| 시나리오 | 신호 | 대응 |
|----------|------|------|
| **인증을 과거처럼 "생략"** | 쿠키에 이름만 넣고 넘어감 (decade_journey 패턴 답습) | **URL 아는 사람 = 전체 데이터 접근**. P3를 독립 게이트로 분리한 이유 (§6.5.2) |
| **첫 클라우드 전환 = 전례 0건** | "로컬에선 됐는데" 가 반복됨 | 로컬 패턴(파일 업로드·상주 워커·로컬 벡터 DB) 답습 금지. P0에 학습 시간 배정 (§6.5.3) |
| **Supabase 무활동 정지** | 며칠 안 쓰다 열면 프로젝트가 정지돼 있음 | keep-alive 핑(Vercel Cron 일 1회) + 매일 쓰는 제품이 되는 것 자체가 근본 완화 (§5.2.3) |
| **무료 티어 백업 없음** | DB 사고 시 복구 불가 | `pg_dump` → GitHub Actions 주기 덤프. Git 레포가 vault + DB 백업 겸용 (§5.2.3) |
| **Supabase 종속** | 무료 정책 변경 시 이전 불가 | 스키마는 표준 Postgres 유지, 전용 기능은 **Auth·Storage로 한정** → Neon 등 이전 경로 확보 |
| **free LLM 쿼터 소진 = 서비스 정지** | 오후에 chat 실패 | extractive fallback을 **1급 경로**로 유지 (이미 있음) |
| 두 시스템 동시 유지 | Mac 앱과 웹 둘 다 고침 | P5를 옵션이 아닌 **필수**로. 병행 운영 기간 명시적 종료일 |
| 스코프 폭발 (기능 추가 유혹) | 웹에서 신기능 착수 | 리팩토링 = **기능 동결**. `FORWARD_DIRECTION` 백로그는 P5 이후 |
| 한국어 검색 품질 저하 | 검색 결과가 로컬보다 나쁨 | P1 게이트를 "동일성"으로 못 박음 (§8) |
| 데이터 유실 | 마이그레이션 중 md/diet 손상 | P0에서 인벤토리 동결 + 읽기전용 스냅샷 백업 |

---

## 10. 한 줄 요약

> **로컬 모델을 위해 존재했던 서버를 걷어내면 서버가 필요 없어진다.**
> 실데이터는 수십 MB, 생성 경로는 이미 클라우드, 미사용 녹음 파이프라인은 폐기 후보.
> 남는 것은 **Vercel + Supabase + GitHub + Groq — 전부 무료 티어, 유료 요소 0개**(§5.2.4)이며,
> `evals/scenarios`가 재구현의 합격선을 정의한다.
> 완료 정의는 하나: **Mac을 꺼도 동작한다.**
