# 개인비서 확장 — 일괄 완료 보고

| Field | Value |
|-------|--------|
| Date | 2026-07-10 |
| Version | App **0.4.0 (14)** · Plan v2.1 delivery |
| Scope | W0 + W1 + W2 + W3(가능분) · OUT/Park 제외 |
| Builds | KnowledgeApp · knowledged · KnowledgeMobile Simulator **OK** |

---

## 1. 한 장 요약

| Wave | 테마 | 상태 |
|------|------|------|
| **W0** | Hub · timeline · RAG 신뢰 | **완료** |
| **W1** | HealthKit · ingest · 빠진 로그 · intent · 주간 버킷 · ⌘⇧R | **완료** |
| **W2** | 크로스 질의 · 출처 · 주간 리뷰 · 인박스 · 메뉴바 · 로컬 알림 · 수면 힌트 · 온보딩 | **완료** |
| **W3** | 음성 ASR 파이프 · Share · EventKit · 위젯 · HTTPS | **의도적 미구현 (EDGE)** |
| **W4+ / Park** | 메일·에이전트·영양 DB·APNs·멀티유저 | **OUT 유지** |

---

## 2. 기능 체크리스트 (한 번에 확인용)

### W0 — 통합 표면
| # | 항목 | 확인 방법 | 상태 |
|---|------|-----------|------|
| 1 | `assistant.today` RPC | 페어링 후 홈 새로고침 / RPC | ✅ |
| 2 | `timeline.list` | 오늘 식사·운동 이벤트 | ✅ |
| 3 | iOS 홈 3블록 (몸/지식/다음) | 홈 탭 | ✅ |
| 4 | Mac 홈 브리핑 | Knowledge.app 홈 | ✅ |
| 5 | RAG 근거 푸터 | 물어보기 → 답 하단 출처 | ✅ |
| 6 | 무검색 솔직 폴백 | 빈 vault 질문 | ✅ (기존) |

### W1 — 몸 + 인지
| # | 항목 | 확인 방법 | 상태 |
|---|------|-----------|------|
| 7 | HealthKit 권한·pull | 설정 → 건강 연결 · 동기화 | ✅ |
| 8 | `health.ingest` 멱등 | 두 번 동기 → accepted/deduped | ✅ |
| 9 | 타임라인 `건강` 배지 | 홈 오늘 목록 | ✅ |
| 10 | 빠진 기록 체크리스트 | 홈 「빠진 기록」 | ✅ |
| 11 | 주간 버킷 API | `assistant.week_review` · 더보기→주간 리뷰 | ✅ |
| 12 | Intent (diet/knowledge/mixed) | `/v1/chat` 자동 분류 | ✅ |
| 13 | Mac ⌘⇧R 녹음 | 캡처 메뉴 | ✅ |

### W2 — 루프·캡처
| # | 항목 | 확인 방법 | 상태 |
|---|------|-----------|------|
| 14 | 크로스 질의 | 「이번 주 단백질이랑 회의」 | ✅ |
| 15 | 출처 투명성 | 답 meta `출처 diet:… · knowledge:…` | ✅ |
| 16 | 주간 리뷰 내러티브 | 더보기 → 주간 리뷰 | ✅ |
| 17 | iOS 인박스 → vault/inbox | 더보기 → 인박스 → vault로 보내기 | ✅ |
| 18 | 메뉴바 한 줄 | Mac 메뉴바 상태 텍스트 | ✅ |
| 19 | 로컬 알림 (빠진 기록) | 17시 이후 갭 있을 때 1회/일 | ✅ |
| 20 | 수면 힌트 | 홈 몸 블록 아래 | ✅ |
| 21 | 연속 기록 streak | 홈 · 주간 리뷰 | ✅ |
| 22 | 비서 온보딩 카드 | Mac 홈 (닫기 가능) | ✅ |
| 23 | 액션 기한 알림 | 기존 ActionDueNotifier 유지 | ✅ (기존) |

### 의도적 비범위 (이번 일괄 납품 제외)
| 항목 | 사유 |
|------|------|
| watchOS 컴플리케이션 | 유지비 · Later |
| 영양 식품 DB · 바코드 | 데이터 지옥 · Park |
| Share Extension · 음성 인박스 ASR | W3 EDGE 무거움 |
| EventKit 읽기/쓰기 | 권한·프라이버시 EDGE |
| iOS 위젯 · App Intents | W3 |
| APNs · HTTPS M5 | 유료 계정·인프라 |
| 메일 · 범용 에이전트 · Mac HK | OUT |
| 메모리 pin/forget 풀 UI | 최소 큐레이션은 미구현 (Next) |

---

## 3. 신규·확장 API

| Method | 용도 |
|--------|------|
| `assistant.today` | 브리핑 + gaps + streak + sleep_hint (v2) |
| `assistant.week_review` | 7일 버킷 + narrative |
| `assistant.gaps` | 빠진 로그만 |
| `timeline.list` | 오늘 이벤트 |
| `health.ingest` / `health.sync_status` | HK 미러 |
| `inbox.create` / `list` / `promote` / `delete` | 텍스트 인박스 |
| `POST /v1/chat` | intent: knowledge \| diet \| **mixed** |

---

## 4. 실기기 검증 순서 (권장 15분)

1. **Mac**  
   - Knowledge.app 실행 → 홈에 오늘/빠진 기록/주간  
   - 메뉴바 한 줄 확인  
   - ⌘⇧R 녹음 토글  
   - 모바일 게이트 페어링 코드 발급  
   - Core gateway 기동 확인  

2. **iPhone**  
   - Xcode Run (0.4.0)  
   - 페어링  
   - 홈 3블록 · 빠진 기록  
   - 설정 → 건강 연결 · 동기화  
   - 더보기 → 인박스 메모 1건 → vault로 보내기  
   - 더보기 → 주간 리뷰  
   - 물어보기 → 혼합 질문 1회 (출처 meta 확인)  

3. **데이터 위치**  
   - `~/Knowledge/services/diet/diet.json`  
   - `~/Knowledge/services/inbox/inbox.json`  
   - `~/Knowledge/vault/inbox/*.md` (promote 후)  

---

## 5. 빌드 명령

```bash
cd ~/IdeaProjects/KnowledgeApp
swift build --product KnowledgeApp
swift build --product knowledged
# iOS
cd Apps/KnowledgeMobile && xcodebuild -scheme KnowledgeMobile \
  -destination 'generic/platform=iOS Simulator' build
```

---

## 6. 문서

| 문서 | 내용 |
|------|------|
| `PERSONAL_ASSISTANT_EXPANSION_PLAN.md` | MECE 전략 v2.1 |
| `PERSONAL_ASSISTANT_EXPANSION_REPORT.html` | HTML 보고서 |
| `ASSISTANT_DELIVERY_REPORT.md` | **본 완료 보고** |
| `core_platform_sketch.md` | RPC 규범 |

---

## 7. 잔여 dogfood 게이트 (코드 외)

| Gate | 담당 |
|------|------|
| G-Dogfood 3일 홈 | 사용자 |
| HK 실워치 데이터 품질 | 사용자 1주 관찰 |
| 자동 로그 삭제율 &lt;10% | 사용자 관찰 |

---

*Implementable Best: W3 EDGE and Park items are explicitly not claimed complete.*
