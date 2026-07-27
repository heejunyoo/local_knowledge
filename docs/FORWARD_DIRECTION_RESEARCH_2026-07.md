# Knowledge 개인비서 — 향후 방향 기능 리서치 보고서

> **2026-07 폐기 — `docs/REFACTOR_DIRECTION_WEB_2026-07.md` §7-1.** 이 문서의 J2(미팅 파이프라인) 관련 서술 및 백로그 F-S1·F-S2·F-S3·F-S4는 미팅 파이프라인 전면 폐기 결정으로 소멸했다(아래 표에 개별 표기). 나머지 백로그는 `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` P6 이후 재평가.

| Field | Value |
|-------|--------|
| **As-of** | **2026-07-10** (시장·기술 스냅샷) |
| **기준 문서** | `ASSISTANT_DELIVERY_REPORT.md` · `PERSONAL_ASSISTANT_EXPANSION_PLAN.md` v2.1 |
| **목적** | “앞으로 나아갈 방향”에 맞는 **후보 기능**을 세계 수준의 제품 리서치 방법론으로 도출·우선순위화 |
| **원칙** | Implementable Best · MECE · 절대 최적 미주장 · 1인·로컬·free-tier 제약 유지 |
| **산출물 성격** | **리서치·방향** (구현 커밋이 아님) |

---

## 0. 리서치 방법론 (총동원 프레임)

본 조사는 단일 벤치마크가 아니라 **다층 방법론 합성**이다.

| 층 | 방법 | 본 보고 적용 |
|----|------|----------------|
| **1. 기준선 (Baseline)** | 납품·갭 보고서 SoT | 보유 자산 / 미완 게이트 / OUT 목록 |
| **2. 외부 환경** | STEEP (Socio·Tech·Eco·Env·Pol) 요약 | 2026-07 시점 시장·규제·플랫폼 |
| **3. 경쟁·대체재** | Competitive teardown + Jobs 대비 | Local AI · IF 앱 · PKM·memory · 플랫폼 Health AI |
| **4. 수요** | JTBD (Jobs To Be Done) | “고용” 단위로 기능 후보 생성 |
| **5. 기회 구조화** | Opportunity Solution Tree (근사) | Desired outcome → opportunity → solution ideas |
| **6. 우선순위** | RICE-lite + Kill matrix 정합 | Reach(본인 사용) · Impact · Confidence · Effort · Strategy Fit |
| **7. 리스크** | Pre-mortem · 프라이버시 경계 | Apple Health+ 등 플랫폼 잠식 시나리오 |
| **8. 검증 설계** | Dogfood gate 정의 | 구현 전 “통과 조건” 선작성 |

**신뢰 한계:** 웹·앱스토어·업계 보도 기반. 내부 사용자 인터뷰 N≥5는 본 조사에 **포함되지 않음** (1인 제품 → 오너 dogfood를 1차 표본으로 둔다).

---

## 1. 기준선 — 우리가 서 있는 곳 (2026-07-10)

### 1.1 이미 가진 차별축 (강화할 자산)

| 자산 | 왜 희소한가 (2026 시장 대비) |
|------|------------------------------|
| **Mac Core + vault SoT + Tailscale thin phone** | 대부분 비서 앱은 클라우드 계정 중심; 로컬 vault 주권은 niche |
| **지식 × 몸 × 하루 한 표면 (Hub)** | IF 앱은 몸 전용, PKM은 지식 전용 — **교차 질의** 가능 제품 드묾 |
| **녹음→전사→요약→확인→vault** | Limitless/Rewind형 “메모리”와 유사 포지션을 **미팅 단위**로 소유 |
| **규칙 ETA + IF + g/ml 대략 계산** | 의료 진단 없이 일상 기록 루프 |
| **cloud free-tier 캐시·throttle** | RPD 절약 설계가 이미 있음 |
| **HK = 참고 전용** 정직 UX | 센서 없을 때도 동작 — 경쟁 앱이 놓치기 쉬운 회복성 |

### 1.2 명시적 구멍 (보고서 직결)

| 구멍 | 전략 함의 |
|------|-----------|
| G-Dogfood 3일 홈 미통과 | “재방문 제품” 증명 전 기능 폭주 금지 |
| whisper MISSING / 실 ASR 필드 | 녹음 루프 신뢰 상한 |
| 요약 extractive 상한 | “읽기 확인” UX는 있으나 **요약 품질 제품 주장 불가** |
| 실 HK 동기 약함 | 몸 자동화 KPI 미달 위험 |
| W3 EDGE 미착수 | 위젯·Share·EventKit·HTTPS — **의도적**이나 도달성 갭 |
| 메모리 pin UI 없음 | 장기 기억 큐레이션 부재 |

### 1.3 전략 불변 (Kill 매트릭스 유지)

- **WIN:** A Hub+Timeline  
- **흡수:** B Health 깊이(부분), C RAG 신뢰, D Capture  
- **OUT:** 메일 에이전트 · 범용 멀티툴 에이전트 · Mac 직접 HealthKit · 의료 진단  

→ 향후 기능 후보는 **이 경계를 넘지 않는 것**만 채택 후보.

---

## 2. 2026-07 외부 환경 (STEEP 요약)

### 2.1 Socio (사용자 기대)

- 개인 AI 어시스턴트 시장 성장·프라이버시 민감도 상승; **local-first가 메인 셀링 포인트**로 이동 (2026 오픈소스/프라이빗 AI 리뷰 공통 메시지).  
- “챗봇”보다 **persistent memory · proactivity · 실행**이 비교 축.  
- 건강·단식 앱은 **HealthKit 연동 + 위젯 + AI 코칭 구독**이 표준 UX.

### 2.2 Tech

- **Hybrid LLM:** 로컬 7B/온디바이스 + 클라우드 free/유료 캐스케이드가 일상 패턴.  
- **RAG 성숙:** “KB 품질(커버리지·신선도·인증) 먼저, 검색 최적화 다음”이 엔터프라이즈 정설 — 개인 vault에도 동일.  
- **Memory companions** (Limitless 등): 화면·음성 로컬 인덱싱 → “그때 뭐라고 했지?” 수요 검증.  
- Apple 생태계: 보고에 따르면 **2026 AI 건강 코치/Health+ 계열 구독** 논의 (Bloomberg/MacRumors 계열 보도) — **HealthKit 데이터 레이어 경쟁 심화** 시나리오.

### 2.3 Eco / Product economics

- 소비자 건강 AI는 구독 모델 지배 (Simple, FastEasy 등).  
- Knowledge 포지션: **유료 건강 구독과 경쟁하지 않고**, “내 노트·내 회의·내 로컬 기록의 허브”로 **보완재** 포지션이 유리.

### 2.4 Pol / Risk

- 건강 조언의 의료 경계 강화 추세 → **진단·처방 톤 금지**, “규칙 계산·기록 코치” 유지 정당.  
- 개인 데이터 유출 스캔들로 **local-first 신뢰 프리미엄** 유지.

---

## 3. 경쟁·대체재 지형 (2026-07)

| 군집 | 대표 유형 (예시) | 강점 | Knowledge 대비 약점 | 배울 점 |
|------|------------------|------|---------------------|---------|
| **A. 범용 클라우드 비서** | ChatGPT · Gemini · Copilot · Lindy류 | 폴·실행·멀티앱 | 데이터 주권·로컬 vault 약 | 프로액티브 제안 UX |
| **B. Local-first AI** | Jan.ai · Khoj · AnythingLLM · 오픈 어시스턴트 | 프라이버시·온프레미스 | 몸·단식·미팅 파이프 약 | 설치 단순성·모델 스위치 |
| **C. 개인 메모리** | Limitless(구 Rewind) 등 | 연속 캡처·검색 | 식단/IF·의도적 미팅 워크플로 약 | 타임라인·검색 UX |
| **D. IF/다이어트 AI** | Simple · FastEasy · 16:8 계열 | 습관 루프·HK·위젯 | 지식 vault·회의 요약 없음 | 단식 시각화·리마인더·배지 |
| **E. 플랫폼 Health AI** | Apple Health+ 보도 궤도 | 센서·OS 통합 | 사용자 vault·로컬 Core 없음 | **차별: 내 노트+회의와 몸 교차** |
| **F. PKM AI** | Notion AI · Obsidian 플러그인 생태계 | 노트 그래프 | 녹음 파이프·몸 루프 약 | 인용·편집 가능 요약 |

**포지셔닝 한 줄 (권고):**  
> “클라우드 코치 앱이 되지 말고, **내 Mac에 사는 지식·몸·하루의 로컬 운영체제**로 깊게.”

---

## 4. JTBD — 앞으로 고용될 일

납품 상태 + 시장을 합성한 **핵심 Job** (MECE).

| Job ID | 사용자가 “고용”하는 일 | 현재 충족 | 갭 |
|--------|------------------------|-----------|-----|
| **J1** | 매일 아침에 “오늘 내 상태”를 30초 파악 | Hub 코드 ✅ | 습관(DAU)·시각 밀도 |
| **J2** | 회의 후 “뭐가 결정됐지?”를 **스스로 읽고** 확정 | 열람 UI ✅ | 요약 품질·점프·실녹음 |
| **J3** | 나중에 “그때 뭐라고 했지?” 검색 | RAG ✅ | 메모리 pin·평가·신선도 |
| **J4** | 단식·체중·식사를 마찰 없이 쌓기 | IF·g/ml ✅ | 리마인더·위젯·HK 실동기 |
| **J5** | “몸 기록 + 회의 맥락”을 한 질문으로 | mixed chat ✅ | 템플릿·주간 내러티브 깊이 |
| **J6** | 폰에서 순간 캡처 → 나중에 Core가 정리 | inbox 텍스트 ✅ | 음성·Share·위젯 |
| **J7** | 민감 데이터는 밖으로 안 나감 | local-first ✅ | 감사 로그·redaction UX |
| **J8** | 앱이 먼저 “빠졌어/기한이야” 말해줌 | gaps·알림 일부 | 프로액티브 정교화 |

---

## 5. 기회 → 기능 후보 (방향에 맞는 것만)

아래는 **구현 스펙이 아니라 리서치 도출 후보**.  
Effort: S≤3일 · M≤2주 · L≥3주 (1인 기준).  
**Fit** = 전략 A + 기존 SoT 재사용.

### 5.1 Tier S — 방향 정합 · 즉시 (Next 2–4주)

| ID | 기능 후보 | 연결 Job | 시장 근거 | Fit | Imp | Eff | 비고 |
|----|-----------|----------|-----------|-----|-----|-----|------|
| **F-S1** | ~~실녹음 dogfood 게이트 패키지~~ (체크리스트+자동 품질 스냅샷) | J2 | 메모리 제품은 “캡처 신뢰”가 핵심 | 5 | 5 | S | **소멸 (2026-07, F-1 미팅 폐기)** |
| **F-S2** | ~~요약 품질 1단계 업~~ (구조화 cloud refine: 결정/액션만 선택적 LLM, 한 줄 강제) | J2 | RAG/KB 품질 먼저 원칙 | 5 | 5 | M | **소멸 (2026-07, F-1 미팅 폐기)** |
| **F-S3** | ~~요약↔전사 타임스탬프 점프~~ | J2 | 리뷰 UX 표준 | 5 | 4 | S–M | **소멸 (2026-07, F-1 미팅 폐기)** |
| **F-S4** | ~~ASR 필드 고정~~ (whisper 설치 스크립트 **또는** Speech-only 명시+배지) | J2 | 도구 신뢰 | 5 | 5 | S | **소멸 (2026-07, F-1 미팅 폐기)** |
| **F-S5** | **메모리 pin / forget 최소 UI** (C1-F3) | J3 J7 | persistent memory 시장 축 | 5 | 4 | M | 계획 Next |
| **F-S6** | **3일/7일 홈 습관 리포트** (로컬 카운터, 설교 없음) | J1 | DAU 게이트 | 5 | 4 | S | G-Dogfood 측정 |
| **F-S7** | **단식 리마인더** (로컬 알림: 종료 30분 전·공복 체중) | J4 | IF 앱 표준 | 5 | 4 | S | 기존 LocalNotify 확장 |
| **F-S8** | **HK 실동기 성공 배지 + 마지막 동기 시각** (참고 전용 유지) | J4 | Health 코치 경쟁 대비 투명성 | 5 | 3 | S | 정직 UX 강화 |

### 5.2 Tier M — 방향 정합 · 중기 (1–2 Wave)

| ID | 기능 후보 | 연결 Job | 시장 근거 | Fit | Imp | Eff |
|----|-----------|----------|-----------|-----|-----|-----|
| **F-M1** | **주간 리뷰 “읽기 전용 스토리” 고도화** (몸+지식 교차 문단, 규칙+선택 LLM) | J5 | 주간 루프·리텐션 | 5 | 4 | M |
| **F-M2** | **크로스 질문 템플릿 칩** (예: “이번 주 단백질 vs 회의 액션”) | J5 | mixed intent 이미 있음 | 5 | 4 | S–M |
| **F-M3** | **iOS 위젯: 단식 남은 시간 / 오늘 몸 한 줄** | J1 J4 | IF·Health 앱 표준 | 4 | 4 | M |
| **F-M4** | **Share Extension → inbox** | J6 | Capture 시장 D 흡수 | 4 | 4 | M |
| **F-M5** | **EventKit 읽기 전용** (오늘 캘린더 → timeline 배경) | J1 | 하루 비서 기대 | 4 | 3 | M |
| **F-M6** | **RAG eval 루프** (고정 질문 세트 hit@k + 오너 채점 UI) | J3 | RAG best practice | 5 | 5 | M |
| **F-M7** | **음식 사진/텍스트 파서 확장** (카메라 없이 붙여넣기 영양 라벨 파싱 등) | J4 | AI 칼로리 앱 경쟁 | 3 | 3 | M | 영양 DB 지옥 주의 |
| **F-M8** | **감사 로그 뷰어** (C7-F4 최소) | J7 | 프라이버시 프리미엄 | 4 | 3 | M |

### 5.3 Tier L / Park — 방향상 매력 있으나 지금은 Kill 또는 지연

| ID | 기능 | 판정 | 이유 |
|----|------|------|------|
| 영양 전수 DB·바코드 | **Park** | 데이터 지옥 · 구독 건강 앱 영역 |
| 의료 진단 톤 코치 | **OUT** | 규제·신뢰 · Apple Health+와 정면 충돌 |
| 메일/메신저 에이전트 | **OUT** | 기존 kill |
| watchOS 컴플리케이션 | **Later** | 유지비 대비 1인 비용 |
| 상시 화면 녹화 메모리 (Rewind형) | **Later/Park** | 가치 크나 TCC·스토리지·윤리적 비용 |
| 멀티유저·HTTPS M5 | **Later** | 계획 EDGE |
| 범용 multi-agent 오케스트레이션 | **OUT** | 범위 폭발 |

---

## 6. 우선순위 합성 (RICE-lite × 전략)

점수: Impact 1–5 · Confidence 1–5 · Effort 1–5(낮을수록 쉬움) · **Score = Imp×Conf×Fit / Effort**.  
Fit 고정 5 for S-tier 전략 정합 항목.

| Rank | ID | Score 감각 | 권고 Wave |
|------|-----|------------|-----------|
| 1 | F-S4 ASR 필드 고정 | 매우 높음 | **즉시** |
| 2 | F-S1 실녹음 dogfood 패키지 | 매우 높음 | **즉시** |
| 3 | F-S2 요약 품질 1단계 | 높음 | **즉시–Next** |
| 4 | F-S3 타임스탬프 점프 | 높음 | **Next** |
| 5 | F-S6 홈 습관 리포트 | 높음 | **Next** |
| 6 | F-S7 단식 리마인더 | 중상 | **Next** |
| 7 | F-S5 메모리 pin | 중상 | **Next** (계획 C1-F3) |
| 8 | F-S8 HK 동기 투명성 | 중 | **Next** |
| 9 | F-M6 RAG eval | 중상 | W2.5 |
| 10 | F-M2 크로스 템플릿 | 중 | W2.5 |
| 11 | F-M3 위젯 | 중 | **W3** (EDGE 허용 시) |
| 12 | F-M4 Share | 중 | **W3** |
| 13 | F-M5 EventKit 읽기 | 중하 | **W3** |

---

## 7. 권고 로드맵 (보고서 방향과 정합)

```
[지금 — 검증·신뢰 스프린트]
  F-S4 ASR 고정
  F-S1 실녹음 1–3건 열람→저장 E2E
  F-S2 요약 품질 1단 (결정/액션 cloud refine + 벤치 N=5)
  F-S6 홈 오픈 카운터 (G-Dogfood 측정)

[다음 — 루프 밀도]
  F-S3 점프 · F-S7 단식 알림 · F-S5 pin · F-S8 HK 투명성
  F-M2 크로스 칩 · F-M6 RAG eval

[이후 — 도달 W3, 게이트 통과 후]
  F-M3 위젯 · F-M4 Share · F-M5 EventKit 읽기
  (HTTPS / 음성 인박스 ASR 는 여력·필요 시)

[절대 지금 안 함]
  영양 전수 DB · 의료 코치 · 메일 에이전트 · Rewind형 상시 녹화
```

**성공 신호 (리서치 권고 KPI):**

| KPI | 목표 (오너 dogfood) |
|-----|---------------------|
| 홈 오픈 | ≥5일/주 |
| 실미팅 확인 완료율 | 전사 열람 후 저장 ≥80% |
| 요약 오너 점수 | 1–5점 평균 ≥3.5 (N≥5) |
| 단식 완료 스트릭 | ≥3회/2주 |
| mixed 질문 | ≥1회/주 |
| HK 참고 동기 성공 | 권한 후 주 1회 이상 accepted>0 (있을 때만) |

---

## 8. Pre-mortem — 이 방향이 실패하는 경우

| 시나리오 | 신호 | 대응 |
|----------|------|------|
| **다이어트 앱으로 고착** | IF·kcal만 쓰이고 확인함 0 | Hub 카피·교차 질문 칩 강제 노출 |
| **Apple Health+에 잠식** | 몸 데이터만 OS에 맡김 | 차별을 **vault+회의+교차**에 고정, 건강 코치 경쟁 금지 |
| **요약 불신** | 저장 전 열람 스킵·삭제 | 품질 1단 + 점프 + 경고 배지 |
| **기능 폭주** | 위젯·Share 동시 착수 | ≤3 동시 규칙 유지 |
| **도구 붕괴** | whisper 장기 MISSING | Speech 전용 모드 공식화 |

---

## 9. 결론 — “앞으로 맞는 기능” 한 페이지

### 9.1 해야 할 일 (방향 정합)

1. **신뢰 인프라:** ASR 필드 · 실녹음 dogfood · 요약 품질 1단 · RAG eval  
2. **읽기 완성:** 타임스탬프 점프 · 품질 경고 · (선택) 모바일 히스토리  
3. **루프 밀도:** 홈 DAU 측정 · 단식 리마인더 · pin/forget · HK 동기 투명성  
4. **교차 가치:** 주간 교차 내러티브 · mixed 템플릿 칩  
5. **도달 (게이트 후):** 위젯 · Share · EventKit 읽기  

### 9.2 하지 말아야 할 일

- 클라우드 건강 코치 카피 · 의료 조언  
- 영양 전수 DB/바코드 올인  
- 메일·범용 에이전트  
- W3를 검증 전에 병렬  

### 9.3 포지션 문장 (2026-07)

> Knowledge는 2026년 시장에서 **“구독형 AI 헬스 코치”가 아니라**,  
> **로컬 vault와 회의 기억을 소유한 채 몸·단식·하루를 한 화면에 묶는 1인 OS**로 간다.  
> 플랫폼 Health AI가 강해질수록, **교차(지식×몸)와 데이터 주권**이 방어 해자이다.

---

## 10. 출처 · 참고 (2026-07 as-of)

### 내부
- `docs/ASSISTANT_DELIVERY_REPORT.md` (2026-07-10)  
- `docs/PERSONAL_ASSISTANT_EXPANSION_PLAN.md` v2.1  
- `docs/FEATURE_SCORECARD_AND_IMPROVEMENT_PLAN.md`  
- `docs/DOGFOOD_RUN_LATEST.log`  

### 외부 (웹 스냅샷, 2026-07 크롤·발행 기준)
- Local-first personal AI 동향: Vellum “8 Best Open-Source Personal AI Assistants in 2026”; First AI Movers local-first enterprise (2026-05)  
- Personal assistant 제품 비교: Mastra “Best Personal AI Assistants of 2026”; Dume “10 Best…2026” (Limitless/Rewind 메모리 포지션)  
- IF/헬스 앱: Apple App Store 리스팅 (Simple, FastEasy, 16:8 계열 — HealthKit·AI 코칭·위젯 패턴)  
- Apple Health AI 보도 궤도: MacRumors/CNET 계열 2025–2026 Health+ / AI health coach 논의  
- RAG: Atlan LLM KB vs RAG; Stack Overflow / IBM RAG 실무 가이드 (KB 품질 우선)  
- 시장 성장·프라이버시: Research and Markets 인용 (Vellum 재인용, personal AI CAGR 서술)

---

## 11. 부록 — 방법론 체크리스트 (재현용)

- [x] 내부 SoT 기준선  
- [x] STEEP 요약  
- [x] 경쟁 6군집  
- [x] JTBD MECE  
- [x] 기회→솔루션 후보  
- [x] Kill/OUT 필터  
- [x] RICE-lite 순위  
- [x] Pre-mortem  
- [x] KPI·Wave 매핑  
- [ ] 외부 사용자 인터뷰 (후속)  
- [ ] 유료 경쟁 앱 실기기 A/B (후속)  

---

*본 문서는 구현 백로그 강제 문서가 아니다. 채택 시 기존 계획의 **동시 ≤3 P0 규칙**을 그대로 적용한다.*
