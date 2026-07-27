# 2026-07 미팅 파이프라인 아카이브

- **왜 아카이브했는가**: `docs/REFACTOR_DIRECTION_WEB_2026-07.md` §7-1(F-1)에서 미팅 녹음 파이프라인을 전면 폐기하기로 결정했다. `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` P0-6에서 관련 정책 자산(스키마·드리프트 시나리오)을 삭제 대신 이동했다.
- **여기 있는 것**: `Schemas/meeting-summary-v1.json`(미팅 요약 스키마), `evals/scenarios/{S02,S02b,S06,S11,S12}*.json`(미팅 상태기계·복구 드리프트 시나리오 5건 — 실측 결과 미팅 폐기와 함께 전부 소멸, §C-1 참조).
- **여기 없는 것**: Swift 코드(`PipelineGraph.swift`, `CrashRecovery.swift`, 미팅 관련 뷰/워커 등)는 P7(레거시 해체)에서 일괄 아카이브한다. 지금 지우면 P0-4 골든 스냅샷 채취가 아직 필요한 다른 검증에 지장을 준다.
- **복원하려면**: 이 디렉토리 전체를 원래 경로(`Schemas/`, `evals/scenarios/`)로 되돌리면 된다. 단 이미 P0-8에서 Mac 앱 쓰기가 동결되었고 P1 이후 데이터가 Supabase로 이관되므로, 복원은 리팩토링 자체를 되돌리는 결정이라 오너 승인이 필요하다.
