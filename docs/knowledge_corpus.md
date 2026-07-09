# Knowledge Corpus — RAG 준비 설계 (SoT)

| Field | Value |
|-------|--------|
| Date | 2026-07-09 |
| Status | **Normative** — RAG Chat 이전 필수 기반 |
| Product | KnowledgeApp (Swift PKM) |
| Supersedes | ad-hoc “지식 가져오기” one-shot UX as the product model |

---

## 0. 왜 지금 막았는가

잘못 간 구현:

- 사용자가 **매번 수동 불러오기** → 지식이 “등록된 소스의 상시 인덱스”가 아니라 일회성 복사
- **미팅 전사·요약**이 제품 핵심인데, 지식 화면과 분리된 것처럼 보임
- RAG Chat을 붙이려면 **단일 검색·검색 단위(chunk)·출처(provenance)** 가 필요한데 FTS 행만 흩어짐

원래 제품 목표 (설계 Rev2 Goals 1–3, KD-2/9):

1. 미팅 파이프라인 → vault 확정본  
2. Notes / Obsidian → 검색 가능 지식  
3. 인덱스(SQLite)는 SoT가 아니라 **derived 검색 계층**

**RAG Chat은 이 코퍼스의 소비자다.** 코퍼스 없이 채팅 UI를 먼저 만들면 안 된다.

---

## 1. 한 줄 모델

```
SoT (파일/Notes/미팅 아티팩트)
    ↓  sync (등록된 소스, 자동·증분)
Derived Corpus (unit + chunk + FTS)
    ↓  retrieve
RAG Chat / 검색 UI
```

사용자는 “파일을 지식으로 복사”하지 않는다.  
**소스를 연결(connect)하면 앱이 코퍼스를 최신으로 유지**한다.

---

## 2. 지식 단위 (Knowledge Unit)

모든 검색·RAG 대상은 하나의 **unit**:

| Field | 의미 |
|-------|------|
| `unit_id` | 안정 id (`meeting:{uuid}`, `notes:{id}`, `obsidian:{relhash}`, `file:{pathhash}`) |
| `source_type` | `meeting` \| `notes` \| `obsidian` \| `file` |
| `title` | 표시 제목 |
| `scope` | `personal` \| `project:…` |
| `sot_kind` | `vault_md` \| `notes_app` \| `local_file` \| `meeting_artifacts` |
| `sot_ref` | vault rel / notes id / abs path / meeting id |
| `content_hash` | 본문(또는 결합 본문) 해시 — 증분 sync |
| `updated_at` | 소스 mtime 또는 파이프라인 시각 |
| `in_corpus` | 검색/RAG 포함 여부 (기본 true) |

### 미팅 unit 본문 구성 (필수 — 처음부터 지식)

미팅은 **녹음→전사→요약** 전체가 지식이다. commit 시 (및 reindex 시) 다음을 **한 unit**으로 합친다:

1. 제목 + one_line_summary  
2. decisions / action_items / key_discussion / unresolved (구조화)  
3. transcript 전문 (또는 segment 연결 텍스트)  
4. vault markdown 경로 포인터 (`sot_ref`)

`source_type=meeting`, `unit_id=meeting:{id}`.  
**review_needed 도 “초안 지식”으로 검색 가능**하되 RAG 기본 필터는 `committed` only (설정으로 완화 가능).

---

## 3. 등록된 소스 (Connected Source) — Import 대체

| source_type | 등록 단위 | SoT | Sync 정책 |
|-------------|-----------|-----|-----------|
| `meeting` | **암시적** (파이프라인) | vault + transcripts/ + summaries/ | **commit / asr.complete / accept 시 자동** |
| `obsidian` | vault root 경로 (기본 `vault_path`) | `.md` 파일 | 앱 기동 + 주기 + “지금 동기화” |
| `notes` | Apple Notes 연결 on/off | Notes.app | 기동 + 주기 + “지금 동기화” (JXA) |
| `folder` | 사용자 선택 폴더 | 로컬 텍스트 파일 | 기동 + 주기 + mtime 증분 |
| `file` | 개별 파일 등록 | 로컬 파일 | mtime/hash 증분 |

UI 카피:

- ❌ “불편한 일회 불러오기”가 제품의 전부  
- ✅ **연결된 소스** + 마지막 동기화 + 문서 수 + **지금 동기화**  
- 파일/폴더는 “선택해서 **연결**” (등록 persistence)

---

## 4. Chunk 계층 (RAG 준비)

FTS 문서 1행 ≠ RAG 최적 단위.  
`knowledge_chunk`:

| Field | 의미 |
|-------|------|
| `chunk_id` | unit 내 순번 포함 |
| `unit_id` | FK |
| `ordinal` | 0..n |
| `text` | ~500–1200자, 문단/세그먼트 경계 |
| `t_start_ms` / `t_end_ms` | 미팅 전사일 때 |
| `content_hash` | 증분 |

**MVP retrieval:** FTS over `chunk.text` (또는 unit body + chunk).  
**Later:** embedding 컬럼 / 벡터 인덱스 (`features.vector_search`).

RAG Chat 1차 구현 시:

1. query → chunk FTS top-k  
2. unit 메타 + 인용 구간  
3. 로컬 LLM 또는 extractive answer  
4. 출처 링크 (vault / Notes / file)

---

## 5. 동기화 알고리즘 (공통)

```
for each connected source:
  enumerate units (files / notes / meetings)
  for each unit:
    h = content_hash(payload)
    if h == stored_hash: skip
    else:
      upsert unit meta
      rebuild chunks
      upsert FTS (unit + optional chunk docs)
```

- **Single-flight** sync (이미 파이프라인과 동일 철학)  
- 실패는 `error_code` + Quiet UI (`failure`만)  
- Notes 자동화 권한 없으면 notes 소스 `degraded` 상태 표시

---

## 6. 파이프라인 결합 (잊으면 안 되는 것)

| 이벤트 | Corpus 동작 |
|--------|-------------|
| `meeting.asr.complete` | draft unit 갱신 (transcript) — RAG 기본 제외 가능 |
| `pipeline → review_needed` | unit 갱신 (summary candidate + transcript) |
| `meeting.review.accept` / commit | **canonical unit** 확정, vault path 연결, RAG 포함 |
| vault md 외부 수정 | obsidian sync가 동일 파일이면 hash로 갱신 |

미팅 지식이 “가져오기” 메뉴 뒤에 숨지 않는다.  
**녹음하는 순간부터 지식 파이프라인**이다.

---

## 7. UI 정보 구조

### 지식 베이스 (구 Sources)

1. **요약 카드:** 전체 unit 수, 미팅/노트/파일 비율, 마지막 전체 sync  
2. **연결됨:** Obsidian path, Notes on/off, 폴더 목록 — 각각 Sync / 연결 해제  
3. **추가:** 폴더 연결, 파일 연결, Notes 켜기  
4. **미팅:** “커밋된 미팅 N건 — 자동 포함” (버튼 없음, 설명만)  
5. 홈 검색 = **전 코퍼스** (이미 FTS; chunk 확장)

### RAG Chat (다음 웨이브 — 코퍼스 이후)

- 입력 → retrieve chunks → answer + citations  
- 필터: scope / source_type / meeting only  

---

## 8. 비목표 (이 문서 범위)

- 클라우드 임베딩 API 필수  
- Notes 양방향 편집  
- 전체 벡터 DB 필수 (KD-8: FTS first)  
- 일회성 import-only UX를 제품 모델로 유지  

---

## 9. 구현 순서

1. [x] **Schema:** `connected_source`, `knowledge_unit`, `knowledge_chunk`  
2. [x] **Corpus service:** sync + meeting index on commit  
3. [x] **Bootstrap auto-sync** + progress/cancel  
4. [x] **UI:** 지식 베이스 = 연결/동기화  
5. [x] **RAG Chat v1:** chunk retrieve + extractive answer + citations (`KnowledgeRAG`)  
6. [x] **RAG Chat v2 path:** llama.cpp when tools present (`LocalLLM` + `rag.use_llama`); else extractive  
7. [x] **Retention:** 수동 삭제/일괄 정리 + `retention.abandoned_days` 기동 시 자동 정리 (vault 유지)

---

## 10. 성공 기준

1. 새 미팅을 확인·저장하면 **추가 클릭 없이** 검색/코퍼스에 등장  
2. Obsidian `vault_path`는 **연결 상태로 자동 sync** (기동 시)  
3. 폴더/파일은 **한 번 연결** 후 재실행해도 유지·재동기화  
4. RAG Chat 착수 시 “먼저 불러오기를 누르세요” 같은 전제 **없음**  
5. 모든 hit에 `source_type` + 열 수 있는 `sot_ref`  

*End of corpus design.*
