# Cloud free-tier 호출·캐시 정책 (2026-07)

| Field | Value |
|-------|--------|
| Status | **Implemented** after audit (was partially missing) |
| Verified | Groq key live + catalog models |

## 정직한 감사 결과 (질문 답)

| 질문 | 감사 전 | 감사 후 |
|------|---------|---------|
| 무료 티어 모델 ID 정확? | 부분 (qwen fallback 위험) | **70B → 8B → Scout** 정합 |
| 과도 호출 방지? | **아니오** (매 질문 cloud) | **캐시 7일 + soft daily cap + interval** |
| Core 저장/캐시? | **아니오** | `~/Knowledge/cache/llm_answer_cache.json` |
| 동일 질문 재호출? | 매번 호출 | **캐시 히트 시 0 호출** |
| 모바일 이중 호출? | chat 실패 시 ask 재시도 | **단일 `/v1/chat` 경로** |
| UI에 엔진/캐시 표시? | 약함 | Mac 말풍선 하단 · 모바일 meta · 설정 usage |

## Groq free rate limits (user table, 2026-07)

| Model | RPD 요지 | 앱 사용 |
|-------|----------|---------|
| llama-3.3-70b-versatile | 1K RPD · 12K TPM | **1순위 품질** |
| llama-3.1-8b-instant | 14.4K RPD · 6K TPM | 70B 실패/한도 시 |
| llama-4-scout | 1K RPD · 30K TPM | 3순위 폴백 |
| whisper / TTS / guard | 별도 | 앱 미사용 |

Soft safety (앱): **하루 400 cloud 호출 상한**, 호출 간 **≥1.2s**, 동일 프롬프트 **7일 캐시**.

## 호출 경로 (의도)

```
User ask
  → retrieve (local, free)
  → extractive fast answer (local)
  → refine once:
        cache hit? → reuse, engine …+cache
        else cloud (70B→8B→Scout) once
        else local 7B
        else keep extractive
```

Meeting one-line polish: cloud only if key (still cached by prompt hash).

## 파일

- `cache/llm_answer_cache.json` — 답 본문 캐시
- `cache/llm_cloud_usage.json` — 일일 호출 카운트
- `config/llm_providers.json` — 모델 카탈로그
- `config/secrets.json` — 키 (600)

## 확실성

- **키·모델·라이브 호출**: 검증됨  
- **캐시·쓰로틀·단일 경로 UI**: 이번 패치로 구현됨 — **dogfood 필수**  
- “영원히 과도 호출 0” 수학적 보장은 없음 (새 질문·새 컨텍스트마다 1회 가능)
