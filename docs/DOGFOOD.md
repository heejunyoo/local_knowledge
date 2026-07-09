# Knowledge 실사용 Dogfood 체크리스트

## 자동 (클릭 없이)

```bash
cd ~/IdeaProjects/KnowledgeApp
export KNOWLEDGE_SKIP_LLM_POLISH=1   # 요약 한 줄 다듬기에서 7B 콜드로드 대기 방지
bash scripts/dogfood-e2e.sh
# 또는
swift run knowledge-dogfood --root ~/Knowledge --reindex --pipeline --commit
```

검증 내용:
1. vault 쓰기 가능  
2. 청크 벡터 재색인 (hash hybrid)  
3. 합성 전사 → `review_needed` → vault commit  
4. post-commit retrieve (토큰 히트)  
5. RAG ask (extractive 또는 LLM)  
6. drift clean  
7. redaction 허용/차단  

**2026-07-09 실측:** `dogfood PASS failures=0`  
- vault: `Meetings/2026/07/dogfood-*.md`  
- pipeline → review_needed → committed  
- retrieve + rag cites=6  

## 모바일 자동 (Mac loopback)

```bash
./scripts/verify-mobile.sh
# health · pair · ask.fast · review.list · diet · revoke 401
```

상세 실기기: [`MOBILE_FIELD_CHECKLIST.md`](./MOBILE_FIELD_CHECKLIST.md)

## 수동 (오너)

| # | 항목 | 확인 |
|---|------|------|
| 1 | `open ~/Applications/Knowledge.app` | 홈·시작 안내 |
| 2 | 화면 기록 권한 (필요 시) | 녹음 |
| 3 | 짧은 실녹음 → 확인함 → 저장 | vault 노트 |
| 4 | 지식 연결 → 지금 동기화 | 벡터/청크 갱신 |
| 5 | 물어보기 질문 | 출처 카드 |
| 6 | 설정 → 모바일 연결 → 페어링 코드 | 6자리 |
| 7 | iPhone Personal Team Run + 페어링 | 검색/물어보기 |
| 8 | (선택) 설정에 Gemini free 키 | 클라우드 1순위 |
| 9 | (선택) `scripts/install-launch-agent.sh` | 상시 데몬 |

## 정직한 한계

- 자동 dogfood는 **합성 전사**로 파이프라인·vault·검색을 검증함. **실마이크/SCK TCC**는 수동.  
- RAG 자동 검증은 기본적으로 **7B 콜드로드를 피함** (속도·안정). UI에서 7B/클라우드 생성은 별도 체감.  
- 디자인은 온보딩·에러 배너 보강 수준이지 “완벽”이 아님.  
