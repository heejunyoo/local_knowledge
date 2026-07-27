# 개인비서 확장 — 납품·갭 보고서

| Field | Value |
|-------|--------|
| Date | **2026-07-10 11:27 KST** |
| Plan | `PERSONAL_ASSISTANT_EXPANSION_PLAN.md` **v2.1** |
| Scope | W0–W2 코드 + post-W2 품질·UX · **정직 갭** |
| Builds (본 시점) | KnowledgeApp · knowledged · KnowledgeMobile Simulator **OK** |
| Related | `DOGFOOD_RUN_LATEST.log` · `UX_GAP_SCORECARD.md` · `FEATURE_SCORECARD_AND_IMPROVEMENT_PLAN.md` · **`FORWARD_DIRECTION_RESEARCH_2026-07.md`** (향후 방향 리서치) |

---

## 1. 한 장 요약 (Executive)

| Wave / 축 | 상태 | 한 줄 |
|-----------|------|--------|
| **W0** Hub · timeline · RAG 신뢰 | **코드 완료** | 3일 홈 DAU 게이트는 **수동 미통과** |
| **W1** HealthKit · ingest · 빠진 로그 | **코드 완료** | 건강 데이터 = **참고 전용**; 실워치 필드 동기 dogfood 별도 |
| **W2** mixed chat · 인박스 · 주간 · 알림 | **코드 완료** | C1-F3 메모리 pin UI 등 Next 잔여 |
| **W3 EDGE** | **의도적 미구현** | 음성 인박스 ASR · Share · EventKit · 위젯 · HTTPS |
| **Post-W2 제품 요청** | **대부분 코드 반영** | 아래 §2 |

**자신감:** “필드에서 매일 쓰는 완성 제품” **주장하지 않음.**  
**가능 주장:** W0–W2 **구현 가능 최선 경로**는 레포에 있고, post-W2 사용자 요청(열람·단식·g/ml·권한 가이드)도 코드로 반영됨.

---

## 2. Post-W2 납품 목록 (계획 문서 이후)

### 2.1 녹음 전사·요약 **직접 열람** (RAG와 분리) — ✅ 코드

| 층 | 산출물 |
|----|--------|
| Core | `MeetingArtifactReader` — 요약 전문 · 전사(시간 라벨) · vault md |
| Mac | 확인함 → **전사·요약 전체 보기** · 탭(요약/전사/노트) · 최근 committed 재열람 |
| iOS | `knowledge.review.get` · 확인함 상세 동일 구조 |
| 테스트 | `MeetingArtifactReaderTests` |

**품질 한계 (정직):** 요약 엔진은 여전히 **extractive + 선택적 한 줄 cloud polish**. 한 줄이 전사 앞부분 기반인 경우가 많아 **의미 압축 품질 벤치(실미팅 N건)는 미실행.** 열람 UI는 갖춤, “요약 퀄리티 검증 완료”는 **아님.**

**UX 잔여:** 요약↔전사 evidence 점프 · 품질 경고 배지 강조 · 모바일 저장 후 히스토리 재열람 약함 · 실녹음 E2E 수동.

### 2.2 간헐적 단식 + 공복 체중 — ✅ 코드

| 항목 | 내용 |
|------|------|
| 시간 선택 | 12 / 14 / 16 / 18 / 20h 칩 |
| 종료 시각 | `내일 오전 h:mm` 형태 미리보기·진행 중 표시 |
| 종료 | 수동 종료 · **첫 식사 기록 시 자동 종료** |
| 체중 | `morning_fasted` 우선 · 건강 체중은 **참고 전용** |
| 참고 블록 | 수면·HK 운동·평균 kcal·TDEE·마지막 식사 후 경과 등 (없어도 단식 가능) |
| ETA | **규칙 계산 (Mifflin + ~7700kcal/kg)** · `plan_uses_ai: false` · AI API 미사용 |

### 2.3 건강 권한 UX — ✅ 코드

| 항목 | 내용 |
|------|------|
| 상태 | `getRequestStatusForAuthorization` 기반 phase |
| 안내 | 설정 → 건강 → 데이터 접근 경로 번호 가이드 |
| 딥링크 | 앱 설정 · 건강 앱(`x-apple-health://`) |
| 홈 | 권한/빈 샘플 시 CTA 배너 |

### 2.4 식단 g/ml → kcal·단백질 자동 계산 — ✅ 코드 (최신)

| 항목 | 내용 |
|------|------|
| 코어 | `DietNutritionCalc` — 100g/100ml 카탈로그 × 분량 |
| 파싱 | `닭가슴살 150g`, `커피 300ml`, `우유 250ml` |
| UI | Mac·iOS 기록 시트: **분량 + g/ml** → kcal/단백질 자동 · 수동 수정 가능 |
| 한 줄 | 동일 파서 · 기존 `400kcal` 입력도 유지 |
| RPC | `diet.estimate_nutrition` |
| 테스트 | `DietNutritionCalcTests` (6) |
| 한계 | **가정용 대략치** · 전수 영양 DB/바코드 아님 |

### 2.5 LLM free tier · 캐시 — ✅ 코드

| 항목 | 내용 |
|------|------|
| 기본 순서 | Groq 70B → 8B/Scout · catalog groq-first |
| 캐시 | `LLMAnswerCache` + soft daily/interval throttle |
| 검증 | `verify-cloud-llm` · dogfood RAG cloud path |

### 2.6 UX 피드백 일관성 · Mac 아이콘 — ✅ 코드

| 항목 | 내용 |
|------|------|
| 토스트 | Mac TossToast · iOS ActionFeedback |
| 식단 삭제/저장 | 실패 삼킴 제거 · 확인·결과 표시 |
| Dock 아이콘 | full-bleed icns · 이중 마스크 제거 |

---

## 3. 계획(v2.1) 대비 매트릭스

### 3.1 W0–W2

| 영역 | ID | 코드 | 자동 dogfood | 필드 | 판정 |
|------|-----|------|--------------|------|------|
| assistant.today / timeline | C7-F1 C3-F1 | ✅ | ✅ | 수동 | 납품 |
| Hub 3블록 | C6-F1 F2 | ✅ | — | 수동 | 납품 |
| RAG citation | C1-F1 | ✅ | score-rag / e2e ✅ | 수동 | 납품 |
| HealthKit + ingest | C2 C7-F2 | ✅ | 합성 ✅ | 실동기 약함 | 코드 납품 / 필드 부분 |
| intent · gaps · week | C5 C3-F2 | ✅ | ✅ | 수동 | 납품 |
| mixed · inbox · 메뉴바 · 알림 | W2 | ✅ | 일부 ✅ | 수동 | 납품 |
| 온보딩 | C7-F3 | ✅ Mac | — | 수동 | 납품 |
| 메모리 pin UI | C1-F3 | ❌ | — | — | **Next** |
| 감사 로그 뷰어 | C7-F4 | ❌ | — | — | **Next** |

### 3.2 W3 EDGE (미착수 · 의도)

음성 인박스 ASR · Share Extension · EventKit · 위젯 · App Intents · HTTPS.

### 3.3 자동 dogfood (최근 스위트)

| 스위트 | 대표 결과 |
|--------|-----------|
| swift test (패키지) | 대부분 PASS · 카탈로그 테스트 groq-first 정합 |
| dogfood-e2e | PASS (RAG cloud + vault) |
| score-rag | hit@3=100 |
| verify-mobile | SMOKE_OK |
| verify-cloud-llm | PASS (Groq) |
| verify-field | PASS (데몬 live 시) |
| verify-tools | **FAIL** — whisper binary/model **MISSING** |
| extended Core HTTP | PASS (diet/chat/inbox/health/fasting 계열) |
| Mac app · icns · groq secret | PASS |

상세 로그: `docs/DOGFOOD_RUN_LATEST.log`.

### 3.4 수동 전용 (에이전트 불가)

- 마이크 / 화면 기록 TCC · 실녹음 1건  
- iPhone Personal Team Run · 실 페어링  
- HealthKit 권한 후 워치 샘플 반영 확인  
- 3일 홈 DAU (W0 G-Dogfood)  
- Dock 아이콘 육안  

---

## 4. API 표면 (누적)

| Method / 경로 | 용도 |
|---------------|------|
| `assistant.today` / `week_review` / `gaps` | 브리핑 · 주간 · 갭 |
| `timeline.list` | 오늘 이벤트 |
| `health.ingest` | HK 미러 (멱등) |
| `inbox.*` | 텍스트 인박스 |
| `POST /v1/chat` | diet / knowledge / **mixed** |
| `knowledge.review.list` / `.accept` / **`.get`** | 확인함 · **전사·요약 전문** |
| `diet.fasting.start` / `.end` / `.status` / `.preview` | 단식 |
| `diet.estimate_nutrition` | g/ml → kcal·단백질 |
| `diet.log_metric` + `morning_fasted` | 공복 체중 |
| LLM 캐시 파일 | `cache/llm_answer_cache.json` · `llm_cloud_usage.json` |

---

## 5. 품질·UX 정직 스냅샷

| 영역 | 점수 감각 (0–10) | 메모 |
|------|------------------|------|
| Hub / 브리핑 | 8 | 코드 완료 · 3일 습관 미측정 |
| RAG 물어보기 | 6–7 | Groq+캐시 · 코퍼스 의존 |
| 확인함 열람 | 7 | UI 경로 명확 · 실녹음 미검증 · 점프/경고 UX 약 |
| 요약 **품질** | 5 | extractive 상한 · 벤치 없음 |
| Diet 기록 | **7.5** | g/ml 자동 계산 추가 · 대략 카탈로그만 |
| IF 단식 | 7 | 시간·종료 시각·참고 블록 |
| Health 권한 | 7 | 가이드+딥링크 · 읽기 거부 확정 불가(iOS 정책) |
| 도구/ASR 필드 | 4 | whisper MISSING · Apple Speech 폴백 |
| 전체 (필드 제품) | **~6.5–7** | “쓸 수 있는 개인 스택” · 폴리시 아님 |

---

## 6. 권장 다음 스프린트 (≤3, 병렬 금지)

| # | 항목 | 이유 |
|---|------|------|
| 1 | **실녹음 1건** 열람→저장→vault→물어보기 | 확인함·요약 게이트 |
| 2 | **whisper 설치** 또는 Speech 경로 필드 고정 | verify-tools FAIL · ASR 신뢰 |
| 3 | C1-F3 pin 최소 UI **또는** 3일 홈 DAU | 계획 Next vs W0 게이트 |

W3 EDGE 병렬 착수 **금지** (Implementable Best).

---

## 7. 빌드·검증 명령

```bash
cd ~/IdeaProjects/KnowledgeApp
swift build --product KnowledgeApp
swift build --product knowledged
swift test --filter 'DietNutritionCalcTests|MeetingArtifactReaderTests|DietStoreTests|LLMRouterTests'
xcodebuild -scheme KnowledgeMobile \
  -project Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj \
  -destination 'generic/platform=iOS Simulator' build
# 선택: bash scripts/dogfood-e2e.sh && bash scripts/verify-mobile.sh
```

---

## 8. 문서 갱신 이력

| 시각 | 내용 |
|------|------|
| 2026-07-10 오전 | W0–W2 일괄 완료 주장 보고 |
| 2026-07-10 중 | dogfood · 권한 · IF · 전사 열람 · 정직 갭 재분석 |
| **2026-07-10 11:27** | **g/ml 영양 자동 계산 반영 · 본 통합 보고서** |

---

## 9. 관련 파일 (구현 앵커)

| 영역 | 경로 |
|------|------|
| 영양 계산 | `Packages/KnowledgeCore/.../DietNutritionCalc.swift` |
| 단식 | `DietStore` fasting · Mac/iOS 식단 카드 |
| 전사 열람 | `MeetingArtifactReader` · `MeetingDetailView` · `ReviewInboxView` · mobile ReviewDetail |
| 건강 권한 | `Apps/KnowledgeMobile/.../HealthKitBridge.swift` |
| LLM 캐시 | `LLMAnswerCache` · `LLMRouter` |
| Dogfood 로그 | `docs/DOGFOOD_RUN_LATEST.log` |
