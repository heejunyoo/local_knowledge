# Knowledge 기능 스코어카드 · 개선 계획

| Field | Value |
|-------|--------|
| Date | 2026-07-10 (갱신 11:27 KST) |
| Scope | Mac app · iOS mobile · Core gateway · Diet · Review read · IF |
| Method | 기능 영역별 0–10 (제품 완성도) → 갭 → 실행 계획 |
| Status | P0 diet UX executed · **post-W2: g/ml auto-kcal, review read, IF** — see `ASSISTANT_DELIVERY_REPORT.md` |

---

## 1. 기능 스코어 (현재)

채점 기준: **10 = 일상 제품으로 자신 있게 쓸 수 있음**, 5 = 동작하나 마찰 큼, 0 = 없음.

| ID | 영역 | 점수 | 한 줄 진단 |
|----|------|------|------------|
| F1 | Mac 녹음→ASR→요약→확인→vault | **8** | 확인함 **전사·요약 전체 보기**; 요약은 extractive 상한; 실미팅 벤치 필요 |
| F2 | Mac 홈 / IA (4탭) | **7** | Hub 브리핑·단식/건강 표면 |
| F3 | Mac 물어보기 (RAG+cloud) | **7** | Groq 우선 + answer cache/throttle |
| F4 | Mac 식단 UX | **8.5** | **g/ml→kcal·단백질 자동** · IF · 공복 체중 |
| F5 | Mac 설정 / 모바일 페어링 | **8** | Core URL·QR·게이트웨이 |
| F6 | iOS 페어링 / 연결 | **8** | 복구 가이드 보강 |
| F7 | iOS 물어보기 | **6.5** | full ask; 품질 서버 의존 |
| F8 | iOS 식단 UX | **8.5** | Mac과 동일 g/ml·IF·공복 |
| F9 | iOS 홈 / 더보기 | **7.5** | HK 권한 CTA · 건강 참고 전용 |
| F10 | Core gateway 안정성 | **8** | review.get · estimate_nutrition · fasting RPC |
| F11 | Diet 데이터/분석 | **7.5** | 소형 카탈로그 자동계산; 전수 DB 없음 |
| F12 | 디자인 시스템 일관성 | **7** | 토스트 일관; SPM 통합 미완 |
| F13 | 보안 (Tailscale·토큰) | **7** | HTTPS 미도입 (M5) |
| F14 | 온보딩 / 에러 회복 | **7** | 건강 권한·페어링 가이드 |
| F15 | 확인함 열람 (신규) | **7** | RAG 분리 열람; evidence 점프·실녹음 E2E 미완 |

**가중 평균 (대략): ~7.4 / 10** — 개인 로컬 스택으로 쓸 수 있음. 폴리시·영양 DB·실필드 ASR 완성은 아님.  
상세: **`docs/ASSISTANT_DELIVERY_REPORT.md`**.

---

## 2. 갭 우선순위 (스코어링 기반)

| P | 갭 | 이유 | 목표 점수 |
|---|-----|------|-----------|
| **P0** | **Diet UX 깊이** (슬롯·시간대 제안·삭제·빠른 칩) | 사용자 직접 지적; 매일 쓰는 표면 | F4/F8 → 8 |
| **P0** | 계획 문서·체크리스트 최신화 | “계획된 작업 마무리” 가시성 | — |
| **P1** | RAG 답 품질 편차 | 키/코퍼스 의존; 프롬프트·topK | F3/F7 → 7+ |
| **P1** | 모바일 홈에 diet suggest 노출 | 식단 습관 루프 | F9 → 8 |
| **P2** | HTTPS / 푸시 (M5) | 유료 계정·인프라 | F13 → 8 |
| **P2** | 단일 Design SPM (iOS+Mac) | 중복 토큰 제거 | F12 → 8 |

**비범위 (이번 계획):** 음식 영양 DB, 바코드, HealthKit 자동 동기, 앱스토어 배포.

---

## 3. 실행 계획 (P0 — 이번 스프린트)

### 3.1 Diet 데이터
- [x] `deleteMeal` / `deleteWorkout`
- [x] `suggestedAction()` 시간대 기반 CTA
- [x] `logMealWithSlot` (아침/점심/저녁/간식 라벨)
- [x] RPC: `diet.delete_*`, `diet.suggest`

### 3.2 Diet Mac UX
- [x] 상단 **제안 카드** (suggestedAction)
- [x] 끼니 **칩** + 자주 쓰는 빠른 추가
- [x] 진행 링/바 가독성
- [x] 목록 **스와이프 삭제**
- [x] 한 줄 NL 유지

### 3.3 Diet iOS UX
- [x] 동일 제안·칩·삭제·링
- [x] 홈 Primary에 diet suggest 반영
- [x] 키보드 dismiss 패턴 유지

### 3.4 문서
- [x] 본 스코어카드
- [x] mobile_plan / phase 갱신

### 3.5 검증
- [x] `swift build` KnowledgeApp + knowledged
- [x] iOS simulator build

---

## 4. 실행 결과 (체크)

| 항목 | 결과 |
|------|------|
| P0 Diet | 구현 완료 — suggest · slots · chips · rings · delete · NL · home CTA |
| 스코어 재산정 F4/F8 | **~8** (습관 UX 성립; 영양 DB 없음으로 10 불가) |
| 모바일 체크리스트 | mobile_plan 화면 표 ✅ 갱신 |
| M5 HTTPS | 미실행 (P2 유지) |
| 앱 버전 | iOS **0.3.0 (10)** |

---

## 5. 다음 스프린트 제안 (P1)

1. RAG: 질문 유형별 프롬프트, citation 강제 한 줄, “모르겠다” 폴백 강화  
2. 클라우드 키 온보딩 1화면 (Mac 설정 상단)  
3. Diet: 주간 목표 달성 배지 / 연속 기록 일수  
4. iOS 홈 위젯 (선택)

---

*Scoring is judgmental product review, not automated metrics.*
