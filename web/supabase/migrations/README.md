# 마이그레이션 — 적용 순서와 대상

## 대상 DB

**ingreed 가 쓰는 Supabase 프로젝트의 `today` 스키마.** 옛 Knowledge 프로젝트
(`gppklwzcmfuuhsefdeik`)는 삭제됐고 되살릴 수 없다. 프로젝트를 새로 하나 더
세우지 않은 이유는 성능이 아니라 **생존**이다 — 개인 앱은 트래픽이 없어 무활동
정지 대상이 되고 이번에 실제로 그렇게 잃었다. ingreed 는 공개 서비스라 깨어 있다.

> ⚠ 이 마이그레이션들은 `ingreed` 스키마를 건드리지 않는다. 적용 전에 대상
> 프로젝트 ref 를 눈으로 확인한다 — ingreed 의 `load_supabase.sh` 가 기본값을
> 두지 않는 것과 같은 이유다.

## 적용 순서

| 순서 | 파일 | 비고 |
|---|---|---|
| 1 | `000_schema.sql` | 스키마·권한·pg_trgm. **anon 에게 아무것도 주지 않는다** |
| 2 | `001_init.sql` | 테이블 14 · 인덱스 |
| 3 | `002_search_functions.sql` | `today.search_docs()` |
| 4 | `003_fix_search_doc_tag_truncation.sql` | tsv 재정의 |
| 5 | `004_rls.sql` | RLS 14 + 정책 14 |
| 6 | `005_diet_metric_context.sql` | |
| — | ~~`006`~~ · ~~`007`~~ | **건너뛴다.** 006 이 만든 것을 007 이 전부 되돌린다. 적용하면 ingreed 프로덕션에 pg_cron·pg_net 이 새로 심긴다 |
| 7 | `008_diet_meal_nutrition.sql` | ingreed 영양 스냅샷 5컬럼 |
| 8 | `009_diet_metric_activity.sql` | 걸음·활동에너지 |

러너는 없다. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <파일>` 로 순서대로
넣거나 Supabase MCP `apply_migration` 을 쓴다(사용자 승인 필요 — 안전 바닥).

## 적용 후

1. **PostgREST 노출 스키마에 `today` 추가** 👤 대시보드 → Settings → API →
   Exposed schemas. 이것을 안 하면 앱이 `PGRST106`(schema not found)을 받는다.
   반대로 이것만으로 데이터가 새지는 않는다 — anon 은 스키마 USAGE 가 없다(000).
2. **Auth 설정을 옮긴다** 👤 — ⚠ **2026-08-21 에 이것을 빠뜨려 로그인이 깨졌다.**
   프로젝트 이전은 DB 만 옮기는 일이 아니다. ingreed 프로젝트는 Auth 를 쓴 적이
   없어 전부 기본값이었고, `site_url` 이 `http://localhost:3000` 이라 프로덕션
   로그인이 성립하지 않았다. 대시보드 → Authentication → URL Configuration,
   또는 Management API `PATCH /v1/projects/{ref}/config/auth`:

   | 키 | 값 |
   |---|---|
   | `site_url` | `https://hj-knowledge.vercel.app` |
   | `uri_allow_list` | `https://hj-knowledge.vercel.app/**,http://localhost:3000/**` |
   | `disable_signup` | `true` — 오너 1인 앱이다. 기본값은 **열려 있다** |

   > 이 설정을 바꾸면 Auth 서버가 재시작되고, 그 직후 발급된 토큰이
   > `PGRST303 JWT issued at future` 로 거부될 수 있다(실제로 겪었다).
   > 1분쯤 뒤 다시 로그인하면 풀린다.

3. **owner 계정 생성** — `scripts/create-owner-user.ts`
4. **데이터 복원** — `scripts/restore-into-today.sh <덤프> `
   (`NEW_OWNER_ID` 필요. 8/9 덤프는 옛 uuid 를 들고 있어 그대로 넣으면 RLS 가
   전부 걸러 "로그인은 되는데 아무것도 안 보이는" 상태가 된다)
5. `npm run test:regression`

## 왜 `public` 이 아닌가

public 에는 ingreed 의 전달 함수(`ingreed_*`)가 산다. 그리고 Supabase 는 public
스키마에 anon 기본 GRANT 를 붙이는 이벤트 트리거를 걸어 둔다 — 거기 개인
데이터를 두면 **RLS 하나가 유일한 방어선**이 된다. `today` 는 새 스키마라 그
트리거가 걸리지 않으므로, 권한은 000 에 적힌 것이 전부다:

- anon → 스키마 USAGE **없음** (PostgREST 가 노출해도 도달 불가)
- authenticated → 도달하되 RLS `owner_id = auth.uid()` 로 자기 행만

ingreed 가 261,257행을 "스키마 미노출 + SECURITY DEFINER" 두 겹으로 막는 것과
같은 층수다.
