# 개인비서 서비스 확장 계획 (MECE)

| Field | Value |
|-------|--------|
| Date | **2026-07-10** |
| Version | **2.1 — Implementable best + strategy kill + P0 compress** |
| Horizon | 2026-07 ~ 2027-Q1 |
| Status | Strategy + **W0 landed** · **W1 HealthKit started** |
| Principle | **현재 상황에서 구현 가능한 최선 (Implementable Best)** — 항상 이 기준 |
| HTML | `docs/PERSONAL_ASSISTANT_EXPANSION_REPORT.html` |
| Related | `FEATURE_SCORECARD_AND_IMPROVEMENT_PLAN.md` · `core_platform_sketch.md` |

---

# §0 운영 원칙 · 전략 대결 · 압축 P0  (v2.1 핵심)

> v2.0 MECE 구조는 유지한다.  
> v2.1은 **“표가 예뻐서 최선”이 아니라, 지금 코드·1인·로컬 스택에서 구현 가능한 최선을 강제**한다.

## 0.1 불변 원칙: Implementable Best

| # | 원칙 | 적용 |
|---|------|------|
| IB1 | **지금 구현 가능한 것**만 P0 | 새 인프라·유료 계정·외부 SaaS 필수 기능은 P0 금지 |
| IB2 | **기존 SoT·RPC 재사용** 우선 | 새 도메인 전에 조립(assistant.today) |
| IB3 | **한 번에 3개 이하** 동시 착수 | Σ≥38 목록 ≠ 전부 병렬 구현 |
| IB4 | **게이트 없는 완료 선언 금지** | W0 = UI 예쁨이 아니라 측정 가능한 DoD |
| IB5 | **2주마다 재채점** | dogfood 없으면 점수 동결·축소 |
| IB6 | **신뢰(RAG)는 허브와 동급 게이트** | 홈만 예쁘고 답이 틀리면 비서 실패 |

## 0.2 전략 대안 Kill 매트릭스 (동일 기준)

채점: 각 0–5, 합 25. 기준 = **1인 · 현재 레포 · 4주 내 dogfood 가치**.

| 기준 | 설명 |
|------|------|
| Fit | 현재 자산(vault+diet+core+mobile) 활용도 |
| Speed | 4주 내 체감 납품 가능성 |
| Diff | 클라우드 챗봇 대비 차별 |
| Risk↓ | 범위·권한·품질 리스크가 낮음 |
| Loop | 매일/매주 재방문 유도 |

| 전략 | Fit | Speed | Diff | Risk↓ | Loop | **Σ** | 판정 |
|------|-----|-------|------|-------|------|-------|------|
| **A. 통합 Hub + Timeline** (지식·몸·하루 한 표면) | 5 | 5 | 4 | 5 | 5 | **24** | **WIN — 채택** |
| **B. Diet/Health 깊이** (영양 DB·HK·습관만) | 4 | 3 | 3 | 3 | 4 | **17** | Kill as sole strategy → **W1 부분 흡수** |
| **C. RAG 신뢰 올인** (지식 답만 끝장) | 5 | 4 | 3 | 4 | 2 | **18** | Kill as sole → **W0 게이트로 흡수** |
| **D. Capture-first** (인박스·음성·Share) | 3 | 3 | 4 | 3 | 3 | **16** | Kill now → **W2** |
| **E. 범용 에이전트/메일** | 1 | 1 | 2 | 1 | 2 | **7** | **OUT 유지** |

**Kill 사유 (한 줄)**

| 전략 | 왜 단독 최선이 아닌가 |
|------|----------------------|
| B | 영양 DB·HK는 가치 있으나, 지식 vault 자산을 방치하면 “다이어트 앱”으로 고착 |
| C | 답 품질은 필수 게이트이나, 매일 여는 표면이 없으면 재방문 실패 |
| D | 캡처는 차별이나 파이프·UX 무거움; Hub 없이 인박스만 늘면 적체 |
| E | 구현·프라이버시·범위 폭발 — 현재 상황 구현 불가에 가깝음 |

**합성 결론 (Implementable Best)**  
> **A를 주전략으로 가되, C의 RAG 최소 신뢰는 W0 동시 게이트, B의 HK는 W1, D는 W2.**  
> “Hub만” 또는 “RAG만” 또는 “헬스만”은 각자 최선이 아니다.

## 0.3 압축 P0 — 진짜 지금 할 일 (최대 3+게이트)

Σ≥38 목록(12+)은 **백로그**다. **동시 구현 P0는 아래만.**

| P0 | ID | 내용 | 왜 구현 가능 최선인가 |
|----|-----|------|----------------------|
| **P0-1** | C7-F1 + C3-F1 | `assistant.today` + 오늘 타임라인 조립 | diet/review **이미 있음** → 신규 SoT 없이 가능 |
| **P0-2** | C6-F1 + C6-F2 | 홈 = 비서 Hub (몸/지식/다음 액션 3블록) | iOS·Mac 홈만 수정 |
| **P0-3** | C1-F1 | RAG 최소 신뢰 (citation 강제 · 근거 없을 때 솔직 폴백) | refine 경로 패치 수준 |

**W0 강제 게이트 (하나라도 실패 시 W0 미완료)**

| Gate | 조건 |
|------|------|
| G-Hub | 홈에서 오늘 몸 한 줄 + 확인함 수 + CTA 1개가 **한 화면** |
| G-API | `assistant.today` RPC 200 + timeline 배열 (빈 날도 스키마 유지) |
| G-Trust | 지식 없을 때 환각 금지; 있을 때 답에 **근거/출처 한 줄** |
| G-Dogfood | 본인이 3일 연속 홈을 1회 이상 염 |

**W0에 넣지 않는 것 (의도적)**  
HealthKit, 주간 리뷰 내러티브, 인박스, 위젯, intent 고도화, 메뉴바, 영양 DB.

**W0 직후 큐 (순서 고정)**  
1. W1: HK pull + `health.ingest` + 빠진 로그  
2. W2: 크로스 질의 · 인박스 · 주간 리뷰  
3. 그 외 Σ 백로그

## 0.4 자신감 선언 (정직)

| 주장 | 수준 |
|------|------|
| A+게이트C 합성 = **현재 제약 하 1순위** | 채택 (kill 매트릭스 근거) |
| 절대·시장 최적 설계 | **주장하지 않음** |
| 점수 Σ 1점 단위 순위 | 참고용; P0는 3개로 고정 |

---

## MECE 문서 지도 (이 문서의 분해 구조)

본 문서는 **상위 주제 “개인비서 확장”** 을 아래 7개 상호배타·전체포괄(MECE) 블록으로만 구성한다.  
블록 간 내용 중복 없음. 모든 기능·결정은 정확히 **하나의 블록**에 귀속된다.

```
L0  개인비서 서비스 확장
│
├── §1  정의·경계          What / What-not     (범위 MECE)
├── §2  현황·문제           Why now             (진단 MECE)
├── §3  사용자 Job          For whom            (Jobs MECE)
├── §4  능력 체계           What capability     (능력 MECE ← 핵심)
├── §5  기능 포트폴리오     What to build       (기능⊂능력, 스코어)
├── §6  실행 로드맵         When / How much     (Wave MECE)
└── §7  거버넌스            How to govern       (리스크·지표·결정)
```

| 블록 | 질문 | 포함 | 제외 (다른 블록) |
|------|------|------|------------------|
| §1 | 무엇을 비서라 하는가? | 정의, In/Out, 원칙 | 기능 목록, 일정 |
| §2 | 왜 확장이 필요한가? | AS-IS 점수, 갭 | 해결책 상세 |
| §3 | 누구의 어떤 일인가? | JTBD만 | UI·API |
| §4 | 어떤 능력 조각으로 쪼개나? | C1–C7 정의·경계 | 개별 기능 스코어 |
| §5 | 어떤 기능을 어떤 순서로? | ID별 스코어·판정 | 주차별 실행 태스크 |
| §6 | 언제 무엇을 납품하나? | Wave 산출물 | 스코어링 방법론 |
| §7 | 어떻게 통제·측정하나? | 리스크, KPI, Decision | 기능 아이디어 |

---

# §1 정의·경계 (Scope MECE)

## 1.1 제품 정의 (한 줄)

> **Mac Core가 데이터 주권·추론·오케스트레이션을 맡고, iPhone(+Watch→HealthKit 브리지)은 얇은 터치포인트로,  
> 「지식 · 몸 · 하루」를 하나의 로컬 개인비서 표면에서 연결하는 시스템.**

## 1.2 범위 분할 — In / Out (상호배타)

전체 가능한 “개인 생산성·헬스·AI” 공간을 세 칸으로만 나눈다.

| 칸 | 정의 | 2026-H2 포함 여부 |
|----|------|-------------------|
| **IN — Core Assistant** | 로컬 SoT 기반 지식·신체·하루 통합, Tailscale Core, thin mobile | **포함** |
| **EDGE — Optional later** | 영양 DB, 위젯, EventKit 읽기, 음성 인박스, HTTPS | **조건부 (W3+)** |
| **OUT — Explicit non-scope** | 범용 에이전트, 메일/메신저, 소셜, Mac 직접 HealthKit, 의료 진단, 멀티유저, 앱스토어 필수화 | **제외** |

```
        ┌─────────────────────────────────────────────┐
        │              개인 디지털 생활 전체            │
        └─────────────────────────────────────────────┘
              │                │                │
              ▼                ▼                ▼
           【 IN 】         【 EDGE 】        【 OUT 】
         본 제품 범위      이후 검토         명시적 비범위
```

## 1.3 설계 원칙 (MECE — 겹치지 않는 규범)

| ID | 원칙 | 의미 | 위반 예 |
|----|------|------|---------|
| P1 | Domain SoT | 도메인별 저장소 1개 | Core에 vault 전문 덤프 |
| P2 | Core = router | 인증·라우팅·브리핑 인덱스만 | Core가 영양 계산 SoT |
| P3 | Thin client | 폰은 UI·센서 브리지 | 폰에 7B·전체 인덱스 |
| P4 | Local-first | Tailscale + 기기 데이터 주권 | 공인 포트 포워딩 |
| P5 | Aggregates first | 숫·이벤트 집계 후 문장 | LLM만으로 칼로리 추정 |
| P6 | Progressive trust | 자동 기록은 source 표시·삭제 가능 | 조용한 덮어쓰기 |

---

# §2 현황·문제 (Diagnosis MECE)

현황 진단은 세 층만 사용한다: **자산 / 성숙도 / 갭**.  
(해결 기능은 §5, 일정은 §6.)

## 2.1 자산 (있는 것)

| 자산군 | 내용 |
|--------|------|
| Knowledge | 녹음→ASR→요약→리뷰→vault · RAG · Mac+iOS |
| Body (Diet) | 식사/운동/목표/ETA · suggest · Core RPC |
| Platform | Core :8741 · pairing · Tailscale · progressive chat |

## 2.2 성숙도 (점수 — 2026-07-10)

| 축 | 점수 | 한 줄 |
|----|------|-------|
| Knowledge | ~7.3 | 필드 사용 가능 |
| Diet UX | ~8 | 습관 루프 성립, 영양 DB 없음 |
| Platform | ~8 | M5 HTTPS 미도입 |
| **Assistant 통합** | **~2** | 도메인 병치, 단일 “오늘” 부재 |

## 2.3 갭 (없는 것 — MECE 네 구멍)

통합 비서 관점에서 공백은 아래 네 가지로만 분류한다 (겹침 없음).

| 갭 ID | 구멍 | 증상 |
|-------|------|------|
| G1 | **통합 표면** | 홈이 도메인 입구 모음; “오늘 나” 없음 |
| G2 | **센서 자동화** | Watch/Health → Core 경로 없음 |
| G3 | **교차 인지** | 지식×몸 혼합 질문·코치 약함 |
| G4 | **재방문 루프** | 주간 리뷰·알림·캡처 인박스 약함 |

---

# §3 사용자 Job (Jobs MECE)

대상: **1인 운영자 / 로컬 파워유저** (본인 dogfood).  
Jobs는 **상황 기준**으로 상호배타 — 한 순간 하나의 primary job.

| Job | When | Want | So that |
|-----|------|------|---------|
| **J1 Orient** | 하루 시작·중간 | 오늘 몸·지식·빈칸을 한 화면 | 앱 전환 없음 |
| **J2 Log body** | 식사·운동 직후 | 최소 마찰로 기록 (가능하면 자동) | 데이터가 쌓임 |
| **J3 Capture mind** | 회의·아이디어 직후 | 10초 유입 | 나중에 검색 |
| **J4 Ask** | 궁금할 때 | 한 도메인 또는 교차 질문 | 맥락 재조립 비용 제거 |
| **J5 Close day** | 잠들기 전 | 빠진 로그만 채움 | 수면 전 마찰↓ |
| **J6 Review week** | 주말 | “이번 주 나” 요약 | 다음 주 조정 |

**Job ↔ 갭 매핑 (중복 없이 primary만)**

| Job | Primary 갭 |
|-----|------------|
| J1 | G1 |
| J2 | G2 |
| J3 | G4 |
| J4 | G3 |
| J5 | G1+G4 (primary G4) |
| J6 | G4 |

---

# §4 능력 체계 (Capability MECE) — 핵심

## 4.1 L1 능력 정의 규칙

1. **Mutually exclusive:** 모든 기능 ID는 정확히 하나의 L1에 속한다.  
2. **Collectively exhaustive:** 개인비서(IN 범위)에 필요한 능력은 C1–C7로 덮는다.  
3. **Layer rule:**  
   - C1–C3 = **도메인 데이터 능력** (무엇을 아는가)  
   - C4 = **유입** (어떻게 들어오는가) — 저장 본문은 C1/C2로 promote  
   - C5 = **인지·오케스트레이션** (데이터 소유 없음)  
   - C6 = **표면** (도메인 로직 없음)  
   - C7 = **플랫폼** (제품 도메인 아님, 실행 기반)

```
                         ┌──────── C5 Cognition ────────┐
                         │  intent · coach · cross-ask  │
                         │     (owns no durable SoT)    │
                         └─────────────┬────────────────┘
           ┌───────────────┬───────────┼───────────┬───────────────┐
           ▼               ▼           ▼           ▼               ▼
        C1 Memory      C2 Body    C3 Time     C4 Ingest        C6 Surface
        (knowledge)    (diet+HK)  (timeline)  (channels)       (UI/notify)
           │               │           │           │               │
           └───────────────┴──── C7 Platform (Core/Tailscale/Auth) ┘
```

## 4.2 L1 카탈로그 (배타 경계 명시)

| L1 | 이름 | 포함 (이 능력만의 책임) | 명시적 제외 (어디로 가나) |
|----|------|-------------------------|---------------------------|
| **C1** | Memory | vault, RAG, 리뷰 큐, 스코프/큐레이션, 회의 지식 | 식사 본문→C2; 타임라인 정렬→C3; 채팅 라우팅→C5 |
| **C2** | Body | 식사·운동·체중·수면 미러, 목표·ETA, HealthKit 매핑 | “오늘 브리핑 UI”→C6; 주간 내러티브→C5 |
| **C3** | Time | 통합 이벤트 인덱스, 오늘/주 버킷, (옵션) 캘린더 읽기 캐시 | 이벤트 원본 SoT→C1/C2; 알림 발송→C6 |
| **C4** | Ingest | 텍스트/음성/Share/단축키 **유입 채널·인박스** | ASR 후 vault 커밋→C1; HK 샘플 저장→C2 |
| **C5** | Cognition | intent 분류, mixed 질의, suggest 로직, 주간 코치 문장, 투명성 | 집계 숫자 SoT→C2/C3; 답 UI→C6 |
| **C6** | Surface | 홈 Hub, 탭 IA, 메뉴바, 위젯, 로컬 알림, empty/copy | API 계약→C7; 브리핑 데이터 조립→C5+C3 |
| **C7** | Platform | pairing, RPC, health.ingest 전송, Tailscale, HTTPS, 온보딩 인프라 | 도메인 스키마 의미→C1–C3 |

## 4.3 L2 분해 (L1 내부 MECE)

### C1 Memory

| L2 | 내용 |
|----|------|
| C1.1 Capture pipeline | 녹음→ASR→요약→리뷰→commit |
| C1.2 Retrieve | 검색·RAG·citation |
| C1.3 Govern | pin/forget/scope |

### C2 Body

| L2 | 내용 |
|----|------|
| C2.1 Manual log | 식사·운동 수동 UX |
| C2.2 Goals | 목표·BMR/TDEE·ETA |
| C2.3 Sensor bridge | HealthKit pull·매핑·dedupe |
| C2.4 Trends | 주간 차트·streak (숫자) |

### C3 Time

| L2 | 내용 |
|----|------|
| C3.1 Timeline index | 다도메인 이벤트 리스트 |
| C3.2 Day/Week buckets | 오늘·이번 주 경계 |
| C3.3 External clock | EventKit 읽기 (EDGE) |

### C4 Ingest

| L2 | 내용 |
|----|------|
| C4.1 Mobile inbox | iOS 텍스트/추후 음성 |
| C4.2 Desktop capture | 메뉴바·단축키 |
| C4.3 System share | Share Extension / Intents (EDGE) |

### C5 Cognition

| L2 | 내용 |
|----|------|
| C5.1 Route | intent → domain RPC |
| C5.2 Coach | suggest, 빠진 로그, 수면 힌트 |
| C5.3 Cross | mixed retrieve + 단일 답 |
| C5.4 Trust UX logic | sources[] 조립 (표시는 C6) |

### C6 Surface

| L2 | 내용 |
|----|------|
| C6.1 Hub | 홈 브리핑·IA |
| C6.2 Domain screens | 식단 탭·물어보기 탭 |
| C6.3 Ambient | 메뉴바·위젯·알림 |

### C7 Platform

| L2 | 내용 |
|----|------|
| C7.1 Edge access | pair, token, Tailscale |
| C7.2 API surface | assistant.* timeline.* health.* |
| C7.3 Ops | 온보딩, 감사 로그, HTTPS |

## 4.4 L1 현재 성숙도 (능력 단위)

| L1 | AS-IS | 12주 목표 | Primary 갭 |
|----|-------|-----------|------------|
| C1 | 7.5 | 8.5 | G3 일부(K1) |
| C2 | 7.0 | 8.5 | G2 |
| C3 | 1.0 | 7.0 | G1 |
| C4 | 4.0 | 6.5 | G4 |
| C5 | 3.0 | 7.0 | G3 |
| C6 | 5.0 | 8.0 | G1 |
| C7 | 8.0 | 8.5 | 지원 |

---

# §5 기능 포트폴리오 (Feature ⊂ Capability)

## 5.1 스코어링 체계 (방법만 여기; Wave 배치는 §6)

| 축 | 약어 | 0–10 의미 |
|----|------|-----------|
| User value | **V** | 주간 빈도 × 고통 제거 |
| Differentiation | **F** | 로컬·Core 차별 |
| Feasibility | **D** | 2026-07 스택으로 가능 |
| Low dependency | **R** | 10=외부 의존 최소 |
| Effort efficiency | **E** | 10=얇은 슬라이스 |

**Σ = V+F+D+R+E (max 50)**

| Σ | 포트폴리오 판정 |
|---|-----------------|
| ≥38 | **Now** |
| 30–37 | **Next** |
| 22–29 | **Later** |
| &lt;22 | **Park** |

## 5.2 기능 레지스트리 (기능은 단일 L1에만 소속)

### C1 Memory

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C1-F1 | RAG 품질 (citation·모르겠음·유형 프롬프트) | 8 | 7 | 8 | 9 | 7 | **39** | Now |
| C1-F2 | 회의→액션 아이템 추출 | 8 | 8 | 6 | 8 | 5 | **35** | Next |
| C1-F3 | 메모리 큐레이션 UI | 6 | 7 | 7 | 9 | 6 | **35** | Next |
| C1-F4 | 프로젝트 스코프 강화 | 5 | 6 | 7 | 9 | 5 | **32** | Next |
| C1-F5 | 이미지 OCR 메모 | 6 | 6 | 5 | 7 | 4 | **28** | Later |
| C1-F6 | Notion/Obsidian 임포트 | 5 | 4 | 4 | 5 | 3 | **21** | Park |

### C2 Body

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C2-F1 | HealthKit pull-on-open | 9 | 8 | 8 | 8 | 7 | **40** | Now |
| C2-F2 | HK→workout/metric 매핑·dedupe | 9 | 8 | 7 | 8 | 6 | **38** | Now |
| C2-F3 | 수면 수치→코치 입력 데이터 | 7 | 8 | 7 | 9 | 6 | **37** | Next |
| C2-F4 | 추세·streak 숫자 고도화 | 6 | 5 | 8 | 9 | 7 | **35** | Next |
| C2-F5 | 물/카페인 로그 | 5 | 4 | 9 | 9 | 8 | **35** | Next |
| C2-F6 | 영양 식품 DB | 8 | 5 | 5 | 6 | 3 | **27** | Later |
| C2-F7 | 바코드/사진 로깅 | 6 | 4 | 4 | 5 | 3 | **22** | Park |
| C2-F8 | watchOS 컴플리케이션 | 7 | 7 | 4 | 6 | 3 | **27** | Later |
| C2-F9 | 약/보충제 | 6 | 5 | 6 | 7 | 5 | **29** | Later |

**C2 센서 경로 (규범):**  
`Watch/iPhone sensors → Apple Health → iOS app → Core health.ingest → DietStore/Timeline`  
Mac 직접 HealthKit = **OUT**.

### C3 Time

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C3-F1 | 통합 타임라인 인덱스 | 9 | 9 | 7 | 9 | 6 | **40** | Now |
| C3-F2 | 주간 버킷 집계 API | 8 | 8 | 7 | 9 | 6 | **38** | Now |
| C3-F3 | EventKit 읽기 전용 | 7 | 6 | 6 | 6 | 5 | **30** | Next |
| C3-F4 | EventKit 쓰기 | 5 | 5 | 4 | 4 | 3 | **21** | Park |
| C3-F5 | 여행/타임존 모드 | 3 | 3 | 8 | 9 | 6 | **29** | Later |

### C4 Ingest

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C4-F1 | iOS 텍스트 인박스 | 8 | 8 | 7 | 9 | 6 | **38** | Now |
| C4-F2 | Mac 전역 캡처 단축키 | 7 | 7 | 8 | 9 | 7 | **38** | Now |
| C4-F3 | iOS 음성→ASR 파이프 | 8 | 9 | 5 | 7 | 3 | **32** | Next |
| C4-F4 | Share Extension | 7 | 7 | 5 | 8 | 4 | **31** | Next |
| C4-F5 | 클립보드 감시 자동저장 | 5 | 6 | 5 | 4 | 3 | **23** | Park |
| C4-F6 | 이메일 IMAP 연결 | 6 | 5 | 3 | 2 | 2 | **18** | Park |

### C5 Cognition

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C5-F1 | Intent 라우터 고도화 | 9 | 9 | 7 | 8 | 5 | **38** | Now |
| C5-F2 | 빠진 로그 체크리스트 로직 | 8 | 7 | 8 | 9 | 7 | **39** | Now |
| C5-F3 | diet.suggest 확장 | 8 | 7 | 8 | 9 | 7 | **39** | Now |
| C5-F4 | 크로스 질의 템플릿 | 8 | 10 | 6 | 8 | 5 | **37** | Next |
| C5-F5 | sources[] 투명성 조립 | 7 | 8 | 7 | 9 | 6 | **37** | Next |
| C5-F6 | 주간 리뷰 내러티브 | 8 | 8 | 6 | 8 | 5 | **35** | Next |
| C5-F7 | 멀티스텝 외부 에이전트 | 4 | 6 | 2 | 2 | 1 | **15** | Park |
| C5-F8 | 상시 로컬 7B 코치 | 6 | 8 | 5 | 7 | 3 | **29** | Later |

### C6 Surface

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C6-F1 | 홈 = Assistant Hub IA | 9 | 8 | 9 | 9 | 8 | **43** | Now |
| C6-F2 | 오늘 브리핑 카드 UI | 9 | 8 | 8 | 9 | 7 | **41** | Now |
| C6-F3 | Mac 메뉴바 한 줄 | 6 | 7 | 8 | 9 | 7 | **37** | Next |
| C6-F4 | 로컬 알림 | 8 | 6 | 6 | 7 | 5 | **32** | Next |
| C6-F5 | iOS 위젯 | 7 | 6 | 6 | 7 | 5 | **31** | Next |
| C6-F6 | App Intents | 6 | 7 | 5 | 8 | 4 | **30** | Next |
| C6-F7 | APNs 원격 푸시 | 6 | 4 | 3 | 4 | 2 | **19** | Park |
| C6-F8 | Siri 단축어 | 5 | 5 | 5 | 7 | 4 | **26** | Later |

### C7 Platform

| ID | 기능 | V | F | D | R | E | Σ | 판정 |
|----|------|---|---|---|---|---|---|------|
| C7-F1 | assistant.today / timeline.* RPC | 9 | 8 | 8 | 9 | 6 | **40** | Now |
| C7-F2 | health.ingest + sync_status | 8 | 7 | 8 | 8 | 6 | **37** | Next* |
| C7-F3 | 온보딩 마법사 | 7 | 5 | 8 | 9 | 6 | **35** | Next |
| C7-F4 | 감사 로그 뷰어 | 4 | 6 | 8 | 9 | 6 | **33** | Next |
| C7-F5 | M5 HTTPS | 5 | 5 | 6 | 6 | 4 | **26** | Later |
| C7-F6 | diet 사이드카 분리 | 4 | 6 | 6 | 8 | 4 | **28** | Later |
| C7-F7 | 멀티유저 | 2 | 3 | 3 | 4 | 2 | **14** | Park |

\*C7-F2는 Σ 37(Next)이나 **C2-F1 Now의 필수 의존** → §6에서 W1에 강제 편성.

## 5.3 포트폴리오 운영 규칙 (v2.1)

| 층 | 의미 | 개수 한도 |
|----|------|-----------|
| **P0 실행** | 이번 스프린트 동시 구현 | **≤3** (+ 게이트) — §0.3 |
| **Now 백로그** | Σ≥38, 순서만 정해 둔 대기 | 무제한, **병렬 금지** |
| **Next / Later / Park** | 기존 표 유지 | — |

### Now 백로그 (Σ≥38) — 실행 순서가 아님

| Rank | ID | L1 | Σ | 실제 배치 |
|------|-----|----|---|-----------|
| 1 | C6-F1 Hub IA | C6 | 43 | **P0-2** |
| 2 | C6-F2 브리핑 UI | C6 | 41 | **P0-2** |
| 3 | C2-F1 HK pull | C2 | 40 | W1 |
| 4 | C3-F1 타임라인 | C3 | 40 | **P0-1** |
| 5 | C7-F1 assistant RPC | C7 | 40 | **P0-1** |
| 6 | C5-F2 빠진 로그 | C5 | 39 | W1 |
| 7 | C5-F3 suggest 확장 | C5 | 39 | P0 홈 CTA로 최소 사용 |
| 8 | C1-F1 RAG 바닥 | C1 | 39 | **P0-3 게이트** |
| 9 | C2-F2 HK 매핑 | C2 | 38 | W1 |
| 10 | C3-F2 주간 버킷 | C3 | 38 | W1–2 |
| 11 | C5-F1 Intent | C5 | 38 | W1 |
| 12 | C4-F1 / C4-F2 캡처 | C4 | 38 | W2 / W1 여력 |
| — | C7-F2 health.ingest | C7 | 37 | W1 강제 의존 |

## 5.4 기존 자산 유지 판정 (MECE: 유지/강화/재배치/축소)

| 자산 | 판정 | 귀속 L1 |
|------|------|---------|
| 녹음→vault | 강화 | C1 |
| RAG 챗 | 강화 | C1+C5 |
| Diet UX | 유지+연결 | C2 |
| Diet ETA | 유지 | C2 |
| Progressive ask | 유지 | C5+C6 |
| QR 페어링 | 유지 | C7 |
| 4탭 IA | **재배치** (홈=Hub) | C6 |

---

# §6 실행 로드맵 (Delivery MECE)

Wave는 **시간 구간이 겹치지 않음**. 각 기능은 **단일 Wave primary**에만 배치.

## 6.1 Wave 정의

| Wave | 기간 | 테마 | 닫는 질문 | 전략 링크 |
|------|------|------|-----------|-----------|
| **W0** | 0–2주 | P0-1·2·3만 | §0.3 게이트 전부 통과? | A + C 게이트 |
| **W1** | 2–6주 | 몸 자동화 + 인지 | HK가 쌓이는가? | B 흡수 |
| **W2** | 6–12주 | 루프·캡처 | 매주 돌아오는가? | D 일부 |
| **W3** | 12–18주 | 시스템 통합 | 밖에서 들어오는가? | EDGE |
| **W4+** | 18주~ | 실험 | go/no-go | — |

## 6.2 Wave × 기능 (배타 배치)

### W0 — Implementable Best slice (P0 only)

| ID | 산출물 | DoD |
|----|--------|-----|
| C7-F1 | `assistant.today` (+ `timeline.list` 최소) | JSON 스키마 안정, 빈 날 OK |
| C3-F1 | 오늘 meal/workout/metric/review 이벤트 조립 | 홈·API 동일 소스 |
| C6-F1·F2 | Mac·iOS 홈 3블록 (몸 / 지식 / 다음) | G-Hub |
| C5-F3 | 기존 `diet.suggest`를 홈 CTA로 연결 | 신규 코치 로직 최소 |
| C1-F1 | refine 답에 근거 푸터; 무검색 시 환각 금지 | G-Trust |

**완료 정의:** §0.3 게이트 4개. Assistant 체감 2→5.  
**비범위:** HK, 인박스, 주간 내러티브, intent 고도화.

### W1 — Body bridge + cognition

| ID | 산출물 | 상태 |
|----|--------|------|
| C2-F1 · C2-F2 | HK pull-on-open + 매핑 | **코드 착수** (iOS HealthKitBridge) |
| C7-F2 | `health.ingest` idempotent | **구현** |
| C5-F1 · C5-F2 | intent · 빠진 로그 | 대기 |
| C3-F2 | 주간 버킷 (숫자) | 대기 |
| C4-F2 | Mac 단축키 | 대기 |

**완료 정의:** 설정에서 건강 연결 1회 → 이후 앱 오픈 시 pull; 운동/수면 source=healthkit 타임라인 배지; dogfood 삭제율 관찰.

### W2 — Retention loop

| ID | 산출물 |
|----|--------|
| C5-F4 · C5-F5 · C5-F6 | 크로스 질의 · 투명성 · 주간 내러티브 |
| C4-F1 | iOS 인박스 |
| C6-F3 · C6-F4 | 메뉴바 · 로컬 알림 |
| C2-F3 · C2-F4 | 수면 입력 · 추세 |
| C1-F2 · C1-F3 | 액션아이템 · 큐레이션 |
| C7-F3 | 온보딩 |

### W3 — Reach

C4-F3, C4-F4, C3-F3, C6-F5, C6-F6, C1-F4, (조건부 C7-F5)

### W4+ / Park

§5 표의 Later·Park 전부. 메일·에이전트·영양 DB 올인·APNs·멀티유저 포함.

## 6.3 아키텍처 납품 (Wave에 묶인 계약만)

```
W0:  assistant.today · timeline.list
W1:  health.ingest · health.sync_status
W2:  inbox.* · assistant.week_review
```

```
User → C6 Surface → C7 RPC → C5 Route
                      ├→ C1 Memory
                      ├→ C2 Body  ← (W1) iOS HealthKit
                      └→ C3 Time  (파생 인덱스, 본문 비복제)
```

## 6.4 90일 체크리스트

**D0–14:** W0 전항목  
**D15–42:** W1 전항목  
**D43–90:** W2 착수 + OKR 중간평가 → W3 go/no-go  

---

# §7 거버넌스 (Risk · Metric · Decision)

§1–6에 없는 통제 장치만 본 절에 둔다.

## 7.1 리스크 레지스터 (유형 MECE)

| 유형 | ID | 리스크 | 완화 |
|------|-----|--------|------|
| 제품 | R-P1 | 기능 폭주 | Wave 게이트, Park 엄격 |
| 제품 | R-P2 | 다이어트 앱 고착 | W0 카피·Hub |
| 데이터 | R-D1 | HK 중복·오류 | source 태그, 수동 우선, 삭제 |
| 데이터 | R-D2 | 크로스 환각 | aggregates first, citation |
| 운영 | R-O1 | Personal Team 7일 | 문서화, 유료는 가치 후 |
| 운영 | R-O2 | Mac off SPOF | W2+ 읽기 캐시 검토 |
| 정책 | R-S1 | 프라이버시 경계 | OUT 목록 계약 |

## 7.2 성공 지표 (KPI MECE: 행동 / 자동화 / 신뢰 / 운영)

| 유형 | KPI | 12주 목표 |
|------|-----|-----------|
| 행동 | 홈 또는 핵심 루프 주간 활성 일수 | ≥5일/주 |
| 행동 | mixed 질문 | ≥1회/주 |
| 자동화 | 운동·수면 중 HK 비율 | ≥50% |
| 신뢰 | 자동 로그 삭제율 | &lt;10% |
| 운영 | 게이트웨이 수동 개입 | ≤1회/월 |

## 7.3 Decision log

| # | 결정 | 날짜 |
|---|------|------|
| D1 | PKM → Personal Assistant 피벗 | 2026-07-10 |
| D2 | 능력 모델 C1–C7 MECE 고정 | 2026-07-10 |
| D3 | W0 = 센서 없이 Hub+Timeline | 2026-07-10 |
| D4 | Health = iPhone→Core only, pull-on-open | 2026-07-10 |
| D5 | Timeline = 파생 인덱스 (Core not dump) | 2026-07-10 |
| D6 | Σ≥38 = Now 백로그; C7-F2 W1 의존 강제 | 2026-07-10 |
| D7 | 메일·범용 에이전트·Mac HK = OUT | 2026-07-10 |
| **D8** | **Implementable Best 상시 원칙 (IB1–IB6)** | 2026-07-10 |
| **D9** | **전략 A 채택; B/C/D/E kill 또는 흡수** | 2026-07-10 |
| **D10** | **P0 = 3개만 (assistant+timeline, Hub, RAG 게이트)** | 2026-07-10 |
| **D11** | **Σ 순위 ≠ 동시 구현 목록** | 2026-07-10 |

## 7.4 한 페이지 결론

| 질문 | 답 |
|------|----|
| 무엇인가? | 로컬 개인비서 OS (C1–C7) |
| 가장 큰 구멍? | C3 Time · C5 Cognition · C2 Sensor · C6 Hub |
| 2주? | W0 Hub + timeline |
| 6주? | W1 HealthKit |
| 안 하는 것? | OUT 칸 전부 |
| 성공? | 매일 홈 · 자동 몸 기록 · 교차 질문 |

---

## Appendix — 문서 이력

| Ver | 변경 |
|-----|------|
| 1.0 | 초기 확장 계획 (나열형 강) |
| 2.0 | 7블록 MECE 재구조 + HTML 보고서 |
| **2.1** | **Implementable Best · kill 매트릭스 · P0 3개 압축 · W0 게이트 · 실행 착수** |

*Scoring: single-operator local-first expert judgment (2026-07-10). Re-score every 2 weeks of dogfood.*
