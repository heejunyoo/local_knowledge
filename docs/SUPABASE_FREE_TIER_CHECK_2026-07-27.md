# Supabase 무료 티어 정책 확인 — 2026-07-27 (P0-9)

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` P0-9. 기억이 아니라 **당일 공식 문서 + 실제 프로젝트(gppklwzcmfuuhsefdeik)** 로 확인했다.

| # | 확인 항목 | 결과 | PASS/FAIL |
|---|---|---|---|
| 1 | 무활동 시 프로젝트 일시정지 기준일 · 복구 방법 | **7일간 "충분한 사용자 DB 활동"이 없으면 일시정지.** 대시보드에서 "Resume project" 클릭 1회로 수동 복구. 일시정지 후 **1년 이내**에만 복구 가능 | **PASS** |
| 2 | keep-alive 핑이 정지 회피에 유효한지 | 공식 문서는 "**user database activity**"를 기준으로 명시 — 대시보드 방문이나 순수 API 호출이 아니라 **실제 DB 쿼리**가 하루 몇 건 필요. 단순 HTTP 헬스체크(REST API 호출)만으로는 불충분할 수 있음 | **PASS (조건부 — 아래 "설계 반영" 참조)** |
| 3 | `pg_cron` 무료 티어 활성 가능 | 실측: `create extension pg_cron` 성공. `select extname, extversion from pg_extension` → `pg_cron 1.6.4` | **PASS** |
| 4 | `pg_trgm` 활성 가능 | 실측: `pg_trgm 1.6` | **PASS** |
| 5 | `pgvector` 활성 가능 | 실측: `vector 0.8.2` | **PASS** |
| 6 | 무료 티어 백업 정책 | 공식 문서: **무료 플랜은 다운로드 가능한 백업을 지원하지 않음**. PITR은 유료 애드온. → **pg_dump 기반 자체 백업이 필수**임을 확정 (D-2b, P2-4 근거) | **PASS** |

**→ 6개 항목 전부 PASS. P1 진입 가능.**

## 상세 근거

### 항목 1·2·6 — 공식 문서
- https://supabase.com/docs/guides/platform/free-project-pausing (확인일 2026-07-27)
  - "A Free plan project is considered inactive if it does not receive sufficient user database activity over the past week."
  - "Typically a few user requests to the database each day over the previous week is enough to keep the project from being paused."
  - 복구: 대시보드 → 조직/프로젝트 선택 → **Resume project**. 일시정지 후 1년 이내 복구 가능.
- https://supabase.com/docs/guides/platform/going-into-prod (확인일 2026-07-27)
  - "Database backups are not available for download for Free Plan projects." PITR은 별도 유료 애드온.

### 항목 3·4·5 — 실측 (프로젝트 `gppklwzcmfuuhsefdeik`, SQL Editor)
```sql
create extension if not exists pg_cron;
create extension if not exists pg_trgm;
create extension if not exists vector;
-- → Success. No rows returned

select extname, extversion from pg_extension where extname in ('pg_cron','pg_trgm','vector');
-- → pg_cron 1.6.4 / pg_trgm 1.6 / vector 0.8.2
```
- 문서만으로는 pg_cron의 무료 티어 가용성에 대해 출처 간 상충하는 정보가 있었다(일부 블로그: "Pro 이상 전용" / Supabase 협력자 GitHub 답변: "모든 티어에서 가능, 리소스로만 제한"). **실측으로 해소** — 이 프로젝트에서는 셋 다 정상 활성화됨.

## 설계 반영 (항목 2에 대한 대응)
- P2-5(keep-alive)는 원래 계획대로 `/api/cron/keepalive`가 **Supabase에 대해 가벼운 `select 1` 쿼리**를 실제로 날리도록 구현한다 (단순 REST 헬스체크 엔드포인트 호출로 대체하지 않는다). 액션플랜 원안이 이미 이렇게 설계되어 있었고, 이번 확인으로 그 설계가 필수임을 확정했다.

## 리전
- 프로젝트가 이미 생성되어 있어(`gppklwzcmfuuhsefdeik`) P1-1의 "서울/도쿄 중 지연 낮은 쪽" 리전 선택은 **기존 프로젝트 리전을 그대로 사용**하는 것으로 실질 확정. 리전 변경이 필요하면 P1-1에서 재확인.
