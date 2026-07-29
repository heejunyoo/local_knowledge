# KnowledgeApp — 프로젝트 진입점

> 사용자 전역 규칙(안전 바닥·작업 방식·톤)은 `~/.claude/CLAUDE.md` 에 있다. 여기엔 이 리포 고유의 것만.

## 착수 전
- 웹 전환 리팩토링 진행 중 → 착수 전 `docs/REFACTOR_STATUS.md` 먼저 Read.

## 이 리포의 집행 장치
- `.claude/settings.json` 의 PreToolUse agent 훅이 `git commit` 을 가로챈다.
  게이트 통과·Phase 완료 같은 **검증 주장**이 커밋 메시지에 있으면 트랜스크립트에서 실제 실행 증거를 찾고, 없으면 차단한다.
- Supabase 는 MCP 로 붙어 있고 `apply_migration`·`execute_sql` 은 사용자 승인(ask)이 강제된다 — 안전 바닥의 "DB 스키마 = Ask-Before-Act".
