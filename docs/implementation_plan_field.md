# Knowledge — Field 구현 계획 (Rev 2026-07-09)

| Field | Value |
|-------|--------|
| Status | **Active** — MVP vertical slice 완료 후 Field 경화 |
| Design SoT | `~/Documents/PKM-native-app-design.md` |
| 외부 참조 | `~/reports/2026-07-09_tauri-heejun-understanding.md` — **철학만** (CaseDesk/Heejun 기능 스펙 아님) |
| 제품 | KnowledgeApp (Swift PKM) — CaseDesk/Heejun 과 **별 제품** |

---

## 0. 한 줄 목표

> **타 Mac에서도 admin 없이**, 외부 서버(Heejun 등) **없이**, `~/Applications/Knowledge.app` 패키지 하나로  
> **시스템 오디오 녹음 → ASR → 요약 → 사람 확인 → Obsidian vault 커밋** 루프가 돈다.

### UI IA (허브 Home)

최상단 **Home 허브** → `AppRoute` 카드로 기능 진입 (확장 = 카드 추가).

| Route | 화면 |
|-------|------|
| `record` | 녹음 · 최근 미팅 |
| `chat` | 지식 Chat (RAG) |
| `library` | 지식 베이스 (코퍼스 연결·동기화) |
| `review` | 확인함 |
| `search` | 전체 검색 |

---

## 1. 프로필

| 프로필 | 대상 | 포함 | 비포함 |
|--------|------|------|--------|
| **Knowledge-Field** (지금) | 오너 Mac / 동료 Mac | 녹음·ASR·요약·리뷰·vault·FTS 인덱스·안정 서명·user-local 데이터 | Windows, Heejun/CS Ops, 필수 클라우드 |
| **Knowledge-Full** (다음) | 오너 심화 | whisper/llama 툴 부트스트랩, Notes FTS 미러, 상시 LaunchAgent, 검색 UI 강화 | 거래/Ops 도메인 |

CaseDesk 문서의 **P-Field** 와 같은 *범위 정의 방법*만 차용. 기능 목록은 공유하지 않는다.

---

## 2. 자급 층 (L0–L3)

| 층 | 의미 | Knowledge 매핑 | Field 필수 |
|----|------|----------------|------------|
| **L0 코드** | 앱+엔진 기동 | `Knowledge.app` + `knowledged` + (옵션 helper) | **예** |
| **L1 설정** | user config | `~/Knowledge/config/app.json` (`vault_path` 등) | **예** |
| **L2 데이터** | 로컬 산출물 | audio / transcripts / summaries / SQLite / vault md | **예** (머신 로컬) |
| **L3 스케줄** | 상시 잡 | 앱 내 daemon tick; 추후 user LaunchAgent | 아니오 (앱 실행 중 tick으로 충분) |

**동일**의 정의 = L0+L1 복제 가능. L2 데이터(오디오·vault 본문)는 기기 로컬 (multi-device 동기화 비목표).

---

## 3. CaseDesk 문서에서 가져올 것 / 버릴 것

### 가져옴 (방법·제약)

- No admin · user-local paths  
- 원격 “본체 서버” 프록시 의존 금지 → **로컬 degrade**  
- 패키지 = 복제 단위; 설치 오케스트레이션은 셸/스크립트  
- 1a 자급 레일 먼저, 1b 배포 포장은 기능 안정 후  
- 시크릿·전문 로그 남발 금지  

### 버림 (다른 제품)

- Heejun `:8000`, CaseDesk 사이드카, DuckDB gold, RID/Ops  
- Tauri/Svelte/Python 재도입  
- Windows portable (Full 이후 재논의)  

---

## 4. 완료된 것 (2026-07-09 기준)

| 항목 | 상태 |
|------|------|
| SwiftUI 앱 + knowledged UDS RPC | 동작 |
| 시스템 오디오 (SCK, Development 서명) | 동작 (`samples`/`peak` 정상) |
| Apple Speech ASR (UI TCC) | 동작 |
| Extractive 요약 + Stage1/2 + coalesce | 동작 |
| `review_needed` → vault commit | 동작 (`~/Obsidian/Main/Meetings/...`) |
| RPC multiplex (EPIPE 수정) | 동작 |
| ad-hoc CDHash 붕괴 → Dev codesign | 완화 |

**Field 수직 슬라이스 = 닫힘.** 이후는 경화·UX·품질·배포.

---

## 5. 웨이브 (재작업 최소화)

```
F0  문서/SoT 정렬          ← 본 문서
F1  제품 표면 경화         ← 지금 구현
F2  설정·vault 신뢰
F3  전사/요약 품질 (optional tools)
F4  Notes 미러 · 검색 UI
F5  타 Mac 설치 검증 (1b)
```

### F1 — 제품 표면 경화

- [x] Home 카피 = in-process Knowledge + `~/Applications/Knowledge.app`
- [x] 상태줄 vault 경로 / 준비 여부
- [x] accept 성공 시 vault 상대경로 + Finder 열기
- [x] review/목록 one-line 미리보기
- [x] README: 제품 경로 · Development 서명 · Field 루프
- [x] `KnowledgePaths` 복구 (레이아웃 SoT)

### F2 — 설정·vault 신뢰

- [x] 기동 시 `vault_path` resolve + 디렉터리 생성 + UI 경고 (`AppConfig`)
- [x] vault 불가 시 accept 차단
- [x] bootstrap-knowledge-root vault 안내 문구

### F3 — 품질 (optional, degrade)

- [x] whisper 없으면 Apple Speech 유지 (daemon hasWhisper 게이트)
- [x] llama 없으면 extractive 유지 + health에 engine 표시
- [x] health: `asr_engine` / `llm_engine` / `whisper_ready` / `llama_ready`
- [x] LLM 체인: **클라우드 무료 티어** → 로컬 **7B** → extractive (`LLMRouter` + `llm_providers.json` 교체 가능)
- [x] 툴 없어도 **silent success 금지** (원칙 유지)

### F4 — Knowledge Corpus (RAG 전제) · 검색

- [x] 설계 SoT: `docs/knowledge_corpus.md` (미팅=1급 지식, 연결·동기화, chunk)
- [x] `connected_source` / `knowledge_unit` / `knowledge_chunk` (schema v2)
- [x] `KnowledgeCorpus`: 미팅 자동 편입 + vault/폴더 연결 sync
- [x] commit / review_needed 시 미팅 unit 인덱싱 (수동 불러오기 불필요)
- [x] UI 「지식 베이스」= 연결·동기화 (one-shot import 모델 폐기)
- [x] 홈 검색 = 전 코퍼스
- [x] RAG Chat v1 extractive (홈「지식 Chat」) — llama 생성은 이후

### F5 — 타 Mac (1b)

- [x] INSTALL 한 장: `docs/INSTALL_FIELD.md`
- [x] `scripts/verify-field.sh` 자체 검증
- [ ] 실제 두 번째 Mac 실측 (오너)

---

## 6. 비목표 (Field)

- CaseDesk/Heejun 통합  
- 클라우드 기본 on  
- 시스템 전역 데몬(admin)  
- vault 본문을 SQLite에만 두기  
- “설정 앱 토글 반복”으로 디버깅하기 (서명·CDHash 원인부터)

---

## 7. 성공 기준 (Field exit)

1. `package-app.sh` → `open ~/Applications/Knowledge.app`  
2. 회의/동영상 소리 재생 중 녹음 → 중지 → `review_needed`  
3. 확인 후 저장 → `{vault}/Meetings/YYYY/MM/{id}.md` 존재, status=`committed`  
4. 재빌드 후에도 Screen Recording 재허용 **상시 불필요** (동일 Dev identity)  
5. 외부 네트워크/Heejun 없이 1–3 재현  

---

## 8. 구현 시 역할 분담 (유지)

| 프로세스 | 책임 |
|----------|------|
| `Knowledge` UI | TCC(캡처·Speech), 녹음 UX, 리뷰, 데몬 lifecycle |
| `knowledged` | 상태 머신, 요약 tick, accept→vault, FTS |
| vault (Obsidian) | 미팅 본문 SoT |
| SQLite | 포인터·상태·검색 인덱스 only |

---

*Field + Design phases closed in code 2026-07-09: hybrid hash vectors, critic Mode B, drift/recovery, redaction, action due, LaunchAgent script. Owner dogfood / 2nd Mac optional.*
