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

## Supabase (P1 완료 — 프로젝트 생성됨: `gppklwzcmfuuhsefdeik`)
| 이름 | 용도 | 사용처 | 상태 |
|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 프로젝트 URL | 브라우저+서버 | 채움 (`web/.env.local`) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | RLS 적용 하 공개 가능 | 브라우저+서버 | 채움 |
| `SUPABASE_SERVICE_ROLE_KEY` | RLS 우회 | **마이그레이션 스크립트 전용**, `web/app`·`web/lib` import 금지 (P3) | 미사용(아래 참고) |
| `SUPABASE_DB_URL` | Postgres 접속 문자열 | 로컬 스크립트 · GitHub Actions 백업 | 채움. **direct(`db.<ref>...:5432`)는 IPv6 전용이라 대부분의 CI/로컬에서 불가 → Session Pooler를 쓸 것.** 아래 §Postgres 직결 참고 |
| `INGEST_API_TOKEN` | Shortcuts `health.ingest` 인그레스 전용 Bearer 토큰(≥32바이트 랜덤) | `/api/health/ingest` 라우트(P4a/P4b에서 라우트 본체 구현 시 사용) | **미채움 — 라우트가 아직 없어 값 발급 보류.** 값은 Shortcuts 앱에만 저장, 문서에 기록 금지 |
| `VAULT_GITHUB_TOKEN` | `knowledge-vault` 레포 Contents API 쓰기 권한 PAT | `web/lib/db/inbox.ts`의 `defaultVaultCommit`/`defaultVaultPathChecker`(inbox.promote, P4a-9) | **미채움 — GitHub PAT 미발급.** 토큰 없이는 `inbox.promote`가 `promote_failed`(error_code=`vault_token_missing`)로 안전하게 실패한다(G4a-2는 발급 후 별도 세션에서 검증). 값은 Vercel 환경변수에만 저장, 문서에 기록 금지 |

### P3 인증 도입 완료 (2026-07-27)
- `web/supabase/migrations/004_rls.sql` 적용됨 — 14개 테이블 전부 RLS 활성화 + `owner_all`(owner_id = auth.uid()) 정책.
- `/api/health/ingest`, `/api/cron/*`, `/login`은 `web/lib/supabase/proxy.ts`의 세션 리다이렉트 제외 경로로 지정됨(라우트 본체는 아직 미구현).

### owner_id placeholder → 실제 오너로 교체 완료 (2026-07-27, P3)
`web/scripts/create-owner-user.ts`로 `naheejun87@gmail.com` 계정을 생성(`auth.uid() = 47e5b22d-a1f1-4266-b4e5-cd2524b0a37f`)한 뒤,
14개 테이블 전부에서 placeholder(`00000000-0000-0000-0000-000000000001`) → 위 uid로 UPDATE 실행 및 실측 확인 완료
(`placeholder_left=0`, 테이블별 행수는 P1 이관량과 일치). 이후 신규 placeholder 데이터가 생기지 않는 한 이 절차는 반복할 필요 없다.

### ★ Postgres 직결 — 반드시 Session Pooler를 쓸 것 (P1 발견 → P2에서 해결·실측 확정)

**문제**: `db.<ref>.supabase.co`는 AAAA 레코드만 존재한다(IPv6 전용, 무료 티어 기본).
IPv6 아웃바운드가 없는 환경에서는 접속이 불가능하다. 실제로 두 번 막혔다.
- P1(로컬 스크립트): `EHOSTUNREACH`
- P2(GitHub Actions 백업): `connection to server at "db.<ref>.supabase.co"
  (2406:da1a:...), port 5432 failed: Network is unreachable` — Actions 러너는 IPv4 전용이다.

**해결**: **Session Pooler(포트 5432)** 를 쓴다. Supavisor는 모든 티어에서 IPv4를 제공한다.

```
postgresql://postgres.gppklwzcmfuuhsefdeik:<password>@aws-1-ap-south-1.pooler.supabase.com:5432/postgres
```

이 프로젝트의 실측 확정값 (2026-07-27, 추측 아님):

| 항목 | 값 | 확인 방법 |
|---|---|---|
| 리전 | **`ap-south-1`** | `db.<ref>` AAAA(`2406:da1a:...`)를 AWS `ip-ranges.json`과 대조 |
| pooler 호스트 | **`aws-1-ap-south-1.pooler.supabase.com`** | `aws-0`은 `ENOTFOUND tenant/user not found`로 거부됨 |
| 사용자명 | **`postgres.<project-ref>`** | pooler는 `postgres`만 주면 `ENOIDENTIFIER` |
| 포트 | **5432 = session** / 6543 = transaction | 덤프·마이그레이션은 session (transaction은 prepared statement 미지원) |
| 서버 버전 | **17.6** | `select current_setting('server_version')` |

> 액션플랜 P1-1은 리전을 "서울/도쿄 중 지연 낮은 쪽"이라 했으나 **실제 프로비저닝은 `ap-south-1`(뭄바이)** 이다.
> 정확한 문자열은 항상 대시보드 **Connect → Session pooler** 에서 확인할 수 있다.
> **리전이나 `aws-N` 번호를 기억·추측으로 조립하지 말 것** — P2에서 이걸로 시간을 크게 낭비했다.

**검증된 사용처**: `pg_dump`(session pooler로 49테이블·1.5MB 덤프 성공),
`knowledge-backup` 레포의 GitHub Actions 백업 워크플로.

**PostgREST 우회는 별개 사안**: `migrate-from-sqlite.ts`/`compare-search.ts`는 P1 당시
이 문제를 우회하려고 PostgREST(HTTPS, anon 키)로 작성했다. RLS가 꺼져 있어 가능했던 것이며
P3에서 RLS를 켜면 막히므로 **일회성 마이그레이션 전용**이다. 앱 런타임(P4a~)의 서버 사이드
DB 접근은 `@supabase/supabase-js`를 쓰고, 스키마 조작·덤프처럼 Postgres 직결이 필요한
도구는 위 session pooler를 쓴다.

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
