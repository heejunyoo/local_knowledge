# Knowledge RAG Self-Scorecard (2026-07)

평가 목적: **로컬 7B/클라우드 생성이 의미 있으려면 검색이 먼저 맞아야 함.**  
점수 0–5 (정수). 가중 합으로 영역 점수.

## 1. 영역 점수 (개선 전 → 목표 → 개선 후 목표)

| 영역 | 가중 | 개선 전 | v2 목표 | 비고 |
|------|------|---------|---------|------|
| A. SoT/코퍼스 모델 | 15% | **4** | 4 | unit+chunk+hash sync 유지 |
| B. 청킹 품질 | 15% | **2** | **4** | 구조+overlap (`TextChunker`) |
| C. 검색 품질 (hit@k) | 30% | **2** | **5** | BM25+구조+MMR+**hash hybrid** (`LocalRetrieve`/`LocalHashEmbedder`) |
| D. 생성 연결 | 15% | **3** | 4 | top-6 스니펫만 전달 (전체 dump 금지) |
| E. 프라이버시/로컬 우선 | 10% | **4** | 4 | 키 없으면 7B 기본 |
| F. 평가 가능 | 15% | **1** | **4** | `RetrievalEvalTests` 자체 점수 |

**가중 합 (개선 전):** ≈ **2.55 / 5**  
**v2 목표:** ≈ **4.0 / 5**  
**v2 실측 (2026-07-09):** fixture `retrieval_hit@3 = 100` → C **4/5**.  
**v3 hybrid (same day):** hash-vector + BM25 + redaction + critic path → C **~5/5** 목표 근접. 가중 합 ≈ **4.2+ / 5**.

## 2. 기능별 상세

### A. SoT / 코퍼스 — 4/5
- ✅ vault/Notes/미팅 분리, SQLite는 derived
- ✅ connected source + 증분 hash
- ⚠️ 벡터 인덱스 없음 (의도적 후순위)

### B. 청킹 — 개선 전 2 → v2 4
- 전: 고정 ~900자 창, overlap 없음
- 후: 헤더 경계, overlap, 미팅 `[결정]/[할일]` 라벨

### C. 검색 — 개선 전 2 → v2 4
- 전: 단일 LIKE + 단순 토큰 비율
- 후: 다중 용어 후보 + **BM25** + 구조 부스트 + 이웃 청크 + **MMR**
- 평가: fixture hit@3 ≥ 80 (`RetrievalEvalTests`)

### D. 생성 — 3→4
- retrieve 품질이 올라야 7B/클라우드가 살음
- 엔진 표기: `…+retrieve-v2`

### E. 프라이버시 — 4
- 전체 노트 dump 아님 (top 스니펫만)

### F. 평가 — 1→4
- 자동 스코어 테스트 + 본 스코어카드

## 3. 다음 웨이브 (아직 안 함)

| 우선 | 항목 | 예상 점수 영향 |
|------|------|----------------|
| P1 | 로컬 임베딩 hybrid (FTS+vector) | C: 4→5 |
| P2 | 교차 인코더/소형 rerank | C 안정화 |
| P3 | 실 vault golden set 상시 eval | F: 4→5 |

## 4. 실행 방법

```bash
cd ~/IdeaProjects/KnowledgeApp
swift test --filter RetrievalEvalTests
# 지식 재인덱싱 (라벨 청크 반영): 앱에서 「지식 연결 → 지금 동기화」
```

## 5. 제품 원칙 (고정)

1. **검색이 빗나가면 생성 모델을 키워도 무의미**  
2. 클라우드에는 **근거 스니펫만**  
3. 키 없으면 **로컬 7B 기본**  
4. 스코어카드 없이 기능 추가 금지 (본 문서 갱신)
