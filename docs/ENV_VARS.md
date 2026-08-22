# 환경변수 이름 매핑 (P0-5 산출물)

> `~/Knowledge/config/secrets.json`, `llm_providers.json`의 **키 이름만** 기록한다. 값은 절대 여기 쓰지 않는다.
> 실제 값은 Vercel(웹) 환경변수·GitHub Actions Secrets(백업 워크플로)에만 저장한다 (P6, P2-4).

## Vercel 프로덕션 배포 (2026-07-29)

| 항목 | 값 |
|---|---|
| Vercel 프로젝트 | `luckyhyun/knowledge-web` (scope `luckyhyun` = 오너 개인 계정) |
| Root Directory | `web` (API로 명시 설정, `sourceFilesOutsideRootDirectory: true`로 리포 루트의 `docs/`·`config/` 정적 import 포함) |
| 프로덕션 URL | `https://web-rho-lovat-34.vercel.app`(alias) — 원 배포 URL은 `https://<deployment-id>-luckyhyun.vercel.app` 패턴 |
| 함수 리전 | **`sin1`(싱가포르)** — `web/vercel.json` 의 `regions`. Supabase 가 `ap-southeast-1` 이라 함수를 DB 옆에 붙인 것이다. 기본값 `iad1`(버지니아)로 두면 요청마다 서울→버지니아→싱가포르를 왕복해 DB 왕복 한 번이 ~230ms 가 된다(2026-08-22 확인). 확인법: `curl -D- <url>/api/cron/keepalive` 의 `x-vercel-id` 가 `icn1::sin1::…` 인지 본다. Hobby 는 단일 리전만 허용한다 |
| 로컬 CLI 링크 | 리포 루트(`KnowledgeApp/.vercel/`)에서 배포할 것 — `web/` 안에서 `vercel --prod`를 실행하면 리포 루트 밖(`docs/`, `config/`) 파일이 업로드에서 빠져 빌드가 깨진다(아래 "Turbopack/Vercel 배포 함정" 참고) |

### ★ Turbopack/Vercel 배포 함정 — 리포 루트 정적 import는 반드시 리포 루트에서 배포할 것

`web/lib/redaction.ts`·`web/lib/llm/catalog.ts`가 `web/` 밖의 `docs/`·`config/` JSON을 정적 import한다(SoT 중복 방지 의도). 두 가지 함정이 있었다:
1. **로컬 dev 서버**: Turbopack이 프로젝트 루트를 `web/`으로 자동 추론해 그 밖 경로를 `Module not found`로 거부 → `web/next.config.ts`의 `turbopack.root: path.join(__dirname, "..")`로 해결(리포 루트 지정).
2. **Vercel CLI 배포**: `web/` 디렉토리 안에서 `vercel --prod`를 실행하면 CLI가 현재 디렉토리(`web/`)만 업로드해 `docs/`·`config/` 자체가 서버에 존재하지 않아 빌드 실패. **리포 루트(`KnowledgeApp/`)에서 `vercel link`+`vercel --prod`를 실행**해 리포 전체를 업로드하고, 프로젝트의 `rootDirectory: "web"` 설정(Vercel API로 지정, `sourceFilesOutsideRootDirectory`는 기본 `true`)이 빌드 시 `web/`을 루트로 쓰되 상위 파일도 포함하도록 해서 해결.

`.vercel/`은 리포 루트·`web/` 양쪽 `.gitignore`에 모두 등록됨.

## 현재 `secrets.json`에 존재하는 키
| 로컬 키 이름 | 용도 | 웹 전환 시 목적지 |
|---|---|---|
| `groq_api_key` | Groq LLM (1순위, `llm_providers.json` order) | Vercel env `GROQ_API_KEY` (P6) |

## `llm_providers.json`에 정의는 되어 있으나 아직 값이 없는 키 (order에 포함, 캐스케이드 2·3순위)
| 프로바이더 | 로컬 `api_key_secret` 이름 | `env_fallback` | 웹 전환 시 목적지 |
|---|---|---|---|
| gemini | `gemini_api_key` | `GEMINI_API_KEY` | Vercel env `GEMINI_API_KEY` (P6, 신규 발급 필요) |
| openrouter | `openrouter_api_key` | `OPENROUTER_API_KEY` | Vercel env `OPENROUTER_API_KEY` (P6, 신규 발급 필요) |

## C2(단식 리마인더) — 이메일 채널 폐기됨(2026-07-29), 신규 키 없음

`RESEND_API_KEY`는 **더 이상 필요하지 않다.** 오너 결정으로 이메일 채널을 전면 폐기하고
"앱 내 표시"로 대체했다 — 리마인더 문구는 이미 `diet-read.ts`의 `fastingStatus()`가
`goal_met`으로 계산해 `label`/`hint`에 담고 있었고 `/diet` 화면이 그걸 렌더링하고 있었다.
이메일이 담당하던 몫은 "앱을 열지 않아도 알려주는" 푸시 성격뿐이라, 그것만을 위해 외부
서비스 계정·API 키·5분 주기 pg_cron·pg_net 아웃바운드를 유지할 가치가 없다고 판단했다.

되돌린 것(`web/supabase/migrations/007_drop_fasting_reminder_cron.sql`): `cron.unschedule`,
`private.trigger_fasting_reminder()` drop, Vault 시크릿 2종(`fasting_reminder_target_url`,
`cron_secret`) 삭제. 코드 쪽은 `web/lib/email/`, `/api/cron/fasting-reminder`,
`FastingSession.reminderSentAt`까지 전부 제거. `private` 스키마와 `pg_net` 확장은 남겼다.

**주의**: Vercel 환경변수 `CRON_SECRET`은 지운 것이 아니다 — `/api/cron/keepalive`가
계속 쓴다. 삭제된 것은 Vault에 복제해 뒀던 사본뿐이다.

## Supabase (P1 완료 — 프로젝트 생성됨: `gppklwzcmfuuhsefdeik`)
| 이름 | 용도 | 사용처 | 상태 |
|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 프로젝트 URL | 브라우저+서버 | 채움 (`web/.env.local` + Vercel Production, 2026-07-29 등록) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | RLS 적용 하 공개 가능 | 브라우저+서버 | 채움 (`web/.env.local` + Vercel Production) |
| `SUPABASE_SERVICE_ROLE_KEY` | RLS 우회 | **마이그레이션 스크립트 전용** 원칙 유지, `web/app`·`web/lib` import 금지 (P3) — **단, `web/lib/health-ingest.ts` 1곳만 예외**(P4b, 2026-07-28 오너 승인): `health.ingest`는 세션 없는 정적 Bearer 인증이라 RLS(`owner_id=auth.uid()`)를 통과할 수 없어 이 파일에서만 service role로 우회하고 owner_id를 코드에서 고정값으로 명시(아래 오너 UUID). 다른 파일로 이 예외를 넓히지 말 것 | 채움(P1부터 `web/.env.local`에 존재, `health-ingest.ts`에서 사용, 2026-07-29 Vercel Production에도 등록) |
| `SUPABASE_DB_URL` | Postgres 접속 문자열 | 로컬 스크립트 · GitHub Actions 백업 | 채움 (`web/.env.local` + Vercel Production). **direct(`db.<ref>...:5432`)는 IPv6 전용이라 대부분의 CI/로컬에서 불가 → Session Pooler를 쓸 것.** 아래 §Postgres 직결 참고 |
| `INGEST_API_TOKEN` | Shortcuts `health.ingest` 인그레스 전용 Bearer 토큰(≥32바이트 랜덤) | `/api/health/ingest` 라우트(`web/lib/ingest-auth.ts`의 `isIngestAuthorized`, P4b에서 라우트 본체 구현 완료) | **채움(2026-07-29)** — `openssl rand -hex 32`로 생성해 Vercel Production 환경변수로 등록 완료. 값은 iOS Shortcuts 앱에도 등록 필요(오너가 직접, 값은 문서에 기록 안 함) |
| `VAULT_GITHUB_TOKEN` | `knowledge-vault` 레포 Contents API 쓰기 권한 PAT | `web/lib/db/inbox.ts`의 `defaultVaultCommit`/`defaultVaultPathChecker`(inbox.promote, P4a-9) | **미채움 — GitHub PAT 미발급.** 토큰 없이는 `inbox.promote`가 `promote_failed`(error_code=`vault_token_missing`)로 안전하게 실패한다(G4a-2는 발급 후 별도 세션에서 검증). fine-grained PAT(레포 `knowledge-vault` 한정, Contents: Read/write)로 발급 권장 — `gh` CLI의 기존 로그인 토큰(`repo` 전체 스코프)은 과도한 권한이라 재사용하지 않음. 값은 Vercel 환경변수에만 저장, 문서에 기록 금지 |
| `CRON_SECRET` | Vercel Cron 인그레스 전용 Bearer 토큰(≥32바이트 랜덤) | `/api/cron/keepalive`(`web/lib/cron.ts`의 `isCronAuthorized`, task 10). ~~`/api/cron/fasting-reminder`~~는 C2 이메일 폐기로 삭제됨 | **채움(2026-07-29)** — Vercel Production 환경변수로 등록 완료. Vault 사본(`cron_secret`)은 007에서 삭제 |
| `GEMINI_API_KEY`/`OPENROUTER_API_KEY` | 위 §"`llm_providers.json`" 참고 | — | **미채움 — 오너 계정 인증이 필요해 대행 불가.** 발급 후 값만 알려주면 `vercel env add`로 등록 대행 가능. (`RESEND_API_KEY`는 2026-07-29 이메일 채널 폐기로 **불필요해짐**) |

### P3 인증 도입 완료 (2026-07-27)
- `web/supabase/migrations/004_rls.sql` 적용됨 — 14개 테이블 전부 RLS 활성화 + `owner_all`(owner_id = auth.uid()) 정책.
- `/api/health/ingest`, `/api/cron/*`, `/login`은 `web/lib/supabase/proxy.ts`의 세션 리다이렉트 제외 경로로 지정됨.
  `/api/cron/keepalive`는 task 10에서 구현 완료(`CRON_SECRET` Bearer 검증). `/api/health/ingest`는 아직 라우트 본체 없음(task 11).

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
