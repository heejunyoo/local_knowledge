# Knowledge 최종 목표 Phase 대비 진척 보고 (갱신)

| Field | Value |
|-------|--------|
| Date | 2026-07-09 (post phase-complete sprint) |
| Design SoT | `~/Documents/PKM-native-app-design.md` Rollout 4 Phase |
| Status | **구현 마감** — 코드/검증 완료; 오너 dogfood·2nd Mac만 운영 잔여 |

---

## 0. Executive summary (최종)

| Phase (Design) | 이전 | **지금** | 판정 |
|----------------|------|----------|------|
| **MVP** | ~90% | **~95%** | 닫힘 (실미팅 1건 dogfood 권장) |
| **Meeting pipeline** | ~75% | **~92%** | SCK + critic Mode B + action due + recovery |
| **Multi-source** | ~85% | **~95%** | BM25 + **hash-vector hybrid** |
| **Automation** | ~25% | **~85%** | drift·redaction·LaunchAgent·flags |

| 프로필 | 진척 |
|--------|------|
| Knowledge-Field | **~98%** |
| Knowledge-Full (설계 비전) | **~88%** |
| **전체 비전** | **~90%** |

**잔여(코드 밖):** 실미팅 1건 커밋, 1주 dogfood, 2nd Mac 실측, (선택) whisper 대용량 모델·dense neural embed.

---

## 1. 이번 스프린트에서 닫은 갭

### Meeting pipeline
| 항목 | 구현 |
|------|------|
| Critic Mode B | `SummaryCritic` + `features.critic` → 파이프라인 분기, hard fail도 확인함으로 복귀 |
| Action due notify | commit 시 `action_item` 적재 + `ActionDueNotifier` + 메뉴바 배지 |
| Crash recovery | `DriftChecker.applyCrashRecovery` 앱 기동 시 실행 |

### Multi-source / RAG
| 항목 | 구현 |
|------|------|
| Hybrid vector | schema **v3** `chunk_vector` + `LocalHashEmbedder` (128-d hashing) |
| Retrieve | BM25 + structure + neighbor + **cosine hybrid** + MMR |
| Fixture hit@3 | **100** |

### Automation
| 항목 | 구현 |
|------|------|
| Drift | vault 포인터·sticky 상태 복구 (`DriftChecker`) |
| Redaction | 클라우드 전 `RedactionPreflight` (차단 시 로컬 7B 폴백) |
| LaunchAgent | `scripts/install-launch-agent.sh` (user-level, no admin) |
| Feature flags | `config/features.json` load/save; field defaults: critic/vector/cloud/notes on |

---

## 2. 검증

```
Tests:           57 selected suites green (PhaseComplete + RAG + Core + …)
retrieval_hit@3: 100
package-app:     ~/Applications/Knowledge.app (Dev sign)
verify-field:    ALL PASSED
```

---

## 3. Phase별 상세 (최종)

### MVP ~95%
- 녹음→ASR→요약→리뷰→vault 전 구간 구현
- 시나리오 S02/S05/S06/S11/S12 runner green
- 잔여: 오너 실미팅 1건 확인

### Meeting pipeline ~92%
- SCK 시스템 오디오 ✅
- Critic Mode B (휴리스틱) ✅ — 2nd model critic 없음 (의도적 light)
- Action due ✅
- Recovery on launch ✅
- 잔여: 1주 연속 dogfood (운영)

### Multi-source ~95%
- Notes/Obsidian/파일 코퍼스 ✅
- Search + RAG Chat ✅
- Hybrid keyword + **local vector** ✅
- 잔여: neural embedding (선택 고도화)

### Automation ~85%
- Drift check + recovery ✅
- Optional cloud + redaction preflight ✅
- Optional vectors (hash) ✅
- LaunchAgent 스크립트 ✅
- 잔여: dense vectors, redaction typed CONFIRM UI, 풀 drift 스케줄 대시보드

---

## 4. 오너 체크리스트 (코드 밖 마감)

1. `open ~/Applications/Knowledge.app`
2. **지식 연결 → 지금 동기화** (청크 벡터 재색인)
3. 실미팅 1건 녹음 → 확인함 → 저장
4. (선택) `bash scripts/install-launch-agent.sh` — 상시 knowledged
5. (선택) 설정에 Gemini free 키
6. (선택) 다른 Mac에서 INSTALL_FIELD + verify-field

---

## 5. 한 장 바

```
MVP              ███████████████████░  95%
Meeting pipeline ██████████████████░░  92%
Multi-source     ███████████████████░  95%
Automation       █████████████████░░░  85%
────────────────────────────────────
전체 비전        ██████████████████░░  ~90%
Field            ███████████████████░  ~98%
```

---

*Phase complete sprint · 2026-07-09 · KnowledgeApp*
