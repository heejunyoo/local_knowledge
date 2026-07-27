# 환경변수 이름 매핑 (P0-5 산출물)

> `~/Knowledge/config/secrets.json`, `llm_providers.json`의 **키 이름만** 기록한다. 값은 절대 여기 쓰지 않는다.
> 실제 값은 Vercel(웹) 환경변수·GitHub Actions Secrets(백업 워크플로)에만 저장한다 (P6, P2-4).

## 현재 `secrets.json`에 존재하는 키
| 로컬 키 이름 | 용도 | 웹 전환 시 목적지 |
|---|---|---|
| `groq_api_key` | Groq LLM (1순위, `llm_providers.json` order) | Vercel env `GROQ_API_KEY` (P6) |

## `llm_providers.json`에 정의는 되어 있으나 아직 값이 없는 키 (order에 포함, 캐스케이드 2·3순위)
| 프로바이더 | 로컬 `api_key_secret` 이름 | `env_fallback` | 웹 전환 시 목적지 |
|---|---|---|---|
| gemini | `gemini_api_key` | `GEMINI_API_KEY` | Vercel env `GEMINI_API_KEY` (P6, 신규 발급 필요) |
| openrouter | `openrouter_api_key` | `OPENROUTER_API_KEY` | Vercel env `OPENROUTER_API_KEY` (P6, 신규 발급 필요) |

## Supabase (P1~ 신규, 아직 미발급)
| 이름 | 용도 | 사용처 |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 프로젝트 URL | 브라우저+서버 |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | RLS 적용 하 공개 가능 | 브라우저+서버 |
| `SUPABASE_SERVICE_ROLE_KEY` | RLS 우회 | **마이그레이션 스크립트 전용**, `web/app`·`web/lib` import 금지 (P3) |

## 기타 로컬 config (값 없이 이름만 확인됨)
| 파일 | 성격 |
|---|---|
| `~/Knowledge/config/mobile_devices.json` (0600) | 모바일 페어링 토큰 스토어 — 웹 전환 후 폐기 (매직링크 인증으로 대체, P3) |

## 격리 조치 기록 (P0-5)
- vault 내 `CyberSourceKey_20250918223005.pem` → `~/Secrets/`로 이동 (2026-07-27). vault에는 참조 노트만 유지.
- vault 내 md 2건에서 **실제 값이 박힌 결제 시크릿** 발견 → 값만 `[REDACTED]`로 치환, 파일/문맥은 유지 (오너 결정):
  - `95 🗑️ 아카이브/2022/토페업무/MID  test_worldpay.md` (live client key + live secret key)
  - `95 🗑️ 아카이브/2022/토페업무/카드 일반 결제.md` (`"secret": "ps_..."` × 4)
  - 이 두 건은 액션플랜 C-5가 원래 열거하지 않았던 신규 발견이다. `.pem`과 달리 **아카이브 폴더 안 마크다운 노트 본문에 인라인**으로 박혀 있었다.
- `postmanv2.html` 확인 — 정적 HTML 기반 Postman 클론 도구, 비밀정보 없음. 조치 불필요.
- **미해결 (P2 착수 전 재검토 필요)**: vault 첨부파일에 개인 PII/금융 문서 3건 발견 (`docs/DATA_INVENTORY_2026-07-27.md` §3 참조: 급여명세서, 재직증명서, 비자 오퍼 레터). 자격증명은 아니므로 P0-5 스코프(G0-3)에는 포함하지 않았으나, `knowledge-vault` 프라이빗 레포에 올리기 전(P2-1) 오너가 유지/제외 여부를 결정해야 한다.
