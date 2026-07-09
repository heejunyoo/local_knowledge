# Knowledge 기능 스코어카드 · 개선 계획

| Field | Value |
|-------|--------|
| Date | 2026-07-10 |
| Scope | Mac app · iOS mobile · Core gateway · Diet |
| Method | 기능 영역별 0–10 (제품 완성도) → 갭 → 실행 계획 |
| Status | **Plan executed in same sprint** (see §4) |

---

## 1. 기능 스코어 (현재)

채점 기준: **10 = 일상 제품으로 자신 있게 쓸 수 있음**, 5 = 동작하나 마찰 큼, 0 = 없음.

| ID | 영역 | 점수 | 한 줄 진단 |
|----|------|------|------------|
| F1 | Mac 녹음→ASR→요약→확인→vault | **8** | 코어 루프 성립; 실미팅 dogfood 지속 필요 |
| F2 | Mac 홈 / IA (4탭) | **7** | Toss 패턴 근접; 더보기 발굴성 보통 |
| F3 | Mac 물어보기 (RAG+cloud) | **6** | 경로 개선됨; 검색 품질·키 유무에 편차 |
| F4 | Mac 식단 UX | **5→8** | 계획 실행 후: 슬롯·제안·삭제·NL |
| F5 | Mac 설정 / 모바일 페어링 | **8** | Core URL·QR·게이트웨이 자동기동 |
| F6 | iOS 페어링 / 연결 | **8** | QR·ATS 우회·실기기 E2E 확인됨 |
| F7 | iOS 물어보기 | **6** | 키보드 수정·full ask; 품질은 서버 의존 |
| F8 | iOS 식단 UX | **5→8** | 계획 실행 후 Mac과 정렬 |
| F9 | iOS 홈 / 더보기 | **7** | Primary CTA; 탭 정리됨 |
| F10 | Core gateway 안정성 | **8** | HTTP·pair loopback·retain 고정 |
| F11 | Diet 데이터/분석 | **6→7** | suggest·delete API; 영양 DB 없음 |
| F12 | 디자인 시스템 일관성 | **6→7** | 토큰·empty·dark; 단일 SPM 패키지 미통합 |
| F13 | 보안 (Tailscale·토큰) | **7** | 개인 mesh; HTTPS 미도입 (의도적 M5) |
| F14 | 온보딩 / 에러 회복 | **6** | 개선됐으나 첫 실행 가이드 여지 |

**가중 평균 (대략): ~7.3 / 10** — “필드에서 쓸 수 있는 제품”, “폴리시 끝”은 아님.

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
