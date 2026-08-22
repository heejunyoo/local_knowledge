# iOS 단축어 — HealthKit 내보내기 가능 항목 조사

작성 2026-08-20 · Sonnet 5 · `research-shortcuts-healthkit` (phase p4-pipe, DISPATCH.md)
**목적**: `.claude/specs/daily-grade/spec.md` 의 활동 축(D-G)에 걸음수·활동에너지를 붙이고, 회복 축을
나중에 수면단계까지 세분화할 가능성에 대비해, iOS 단축어 앱이 HealthKit 에서 실제로 무엇을 꺼내
`/api/health/ingest` 로 보낼 수 있는지 확인한다. 코드는 고치지 않는다 — 이 문서 하나만 산출물이다.

**전제**: 리포에 네이티브 HealthKit 리더가 없다(`HKQuantityTypeIdentifier` 0건, `grep -rn` 으로 재확인함).

> **정정(2026-08-22)**: 위 "`HKQuantityTypeIdentifier` 0건 → 네이티브 리더 없음" 판정은 **근거가 틀렸다.**
> 그 리터럴이 나오는 파일은 이 문서를 포함한 문서 4개뿐이고, 실제 코드는
> `HKQuantityType.quantityType(forIdentifier: .bodyMass)` 형태라 그 grep 에 걸리지 않는다.
> 네이티브 리더는 `Apps/KnowledgeMobile/Sources/HealthKitBridge.swift` 에 **있다**(운동·수면·체중, pull-on-open).
> 다만 그 경로의 목적지는 클라우드가 아니라 Tailscale 너머의 맥이고 Mac 앱은 쓰기 동결(P0-8)이라,
> **"웹으로 들어오는 경로는 단축어뿐"이라는 결론 자체는 유효하다.** 근거만 교체한다.
> 설정 절차는 `docs/HEALTH_INGEST_SHORTCUT.md`.

유일한 유입 경로는 단축어의 "건강 샘플 찾기"(Find Health Sample / Find Health Samples Where) 액션이다.

**조사 방법의 한계**: Apple 공식 문서는 이 액션의 Type(유형) 드롭다운 전체 목록을 정적 페이지로 게시하지
않는다 — 이번 조사에서 Apple 공식 가이드 페이지 여러 개(`support.apple.com/guide/shortcuts/...`)를
직접 열었으나, 하나는 리다이렉트되어 일반 가이드 목차만 나왔고, 다른 하나("What's new in Shortcuts",
`support.apple.com/en-us/101583`)는 도구가 "본문이 너무 길어 잘렸다"고 반환해 내용을 확인하지 못했다.
확인된 것은 Apple 공식 릴리스노트의 다른 버전 페이지(`.../apd6f00fefa5/5.0/ios`, Shortcuts 15.5)에서
`"The Find Health Sample action no longer causes a crash when you add a filter for Source."` 한 줄뿐
— 이 액션이 Apple 이 실제로 유지보수하는 공식 네이티브 액션이라는 것은 이걸로 확인되지만, Type 목록은
여전히 확인 못 함. 그래서 이 문서의 판정은 공식 카탈로그가 아니라 **실제로 이 액션을 써서 값을 받아본
개발자들의 1차 후기(직접 연 페이지)** 에 근거한다. 검색엔진 요약문(스니펫)만 있고 원문을 열지 못한
자료는 근거로 쓰지 않았다 — 아래 표에 "확인 못 함"으로 별도 표시했다.

## 판정 표

| 항목 | 판정 | 근거 |
|---|---|---|
| 걸음수 (Steps) | **가능** | Maxime Heckel, *Using Shortcuts and serverless to build a personal Apple Health API* — 원문 열람 확인(WebFetch, <https://blog.maximeheckel.com/posts/build-personal-health-api-shortcuts-serverless/>). 저자가 단축어의 "건강 샘플 가져오기" 액션으로 Steps 를 실제로 가져와 "Steps measurements are grouped by hour"라고 확인했고, `steps: { count: '409\n5421\n70...', date: '2020-11-02T00:00:00...' }` 형태의 JSON payload 로 서버리스 함수에 전송하는 전체 구현을 공개했다. 같은 글에서 일반 Heart Rate 도 같은 방식으로 가져왔다(단, Resting Heart Rate 아님 — 아래 참고) |
| 활동에너지 (Active Energy) | **불확실** | 이번 조사에서 직접 연 페이지 중 "Active Energy/Active Calories 를 건강 샘플 가져오기 Type 으로 선택해 값을 받았다"를 명시적으로 확인한 1차 후기는 없었다. (a) Katie Brady, *iOS Shortcut: Energy Balance* (Medium) — Active Calories 필터를 다룬다는 검색 스니펫이 있었으나 페이지 자체는 403 Forbidden 으로 원문 열람 실패. (b) RoutineHub 의 "Active Energy" 단축어(<https://routinehub.co/shortcut/1480/>) — 열람 시도 시 403 으로 원문 확인 실패. (c) Health Exporter & Shortcuts 앱 App Store 페이지(원문 열람 확인, <https://apps.apple.com/no/app/health-exporter-shortcuts/id6759006922>) 는 "Activity: Step Count, Walking Distance, Active Calories..."로 Active Calories 내보내기를 명시하지만, 이 앱 자체는 "Read-only HealthKit access"(자체 HealthKit 리더)를 쓴다고만 적혀 있어 단축어의 네이티브 "건강 샘플 가져오기" 액션을 쓰는지는 이 페이지만으로 구분 불가. (d) heartbridge README(원문 열람 확인, 아래 참고)는 "Heartbridge supports pretty much any Health record exported by Shortcuts"라는 포괄적 문구는 있으나 Active Energy 를 이름으로 콕 집어 나열하지는 않는다. Steps·Resting Heart Rate 가 이미 확인된 같은 액션의 Type 옵션이라는 점에서 가능성은 높아 보이나, 이는 정황 추정이며 이번 조사로 직접 확인한 사실이 아니다 |
| 안정시심박 (Resting Heart Rate) | **가능** | heartbridge (GitHub, mm/heartbridge) README 원문 열람 확인(WebFetch, raw 파일 <https://raw.githubusercontent.com/mm/heartbridge/main/README.md>, 저장소 <https://github.com/mm/heartbridge>). README 가 지원 데이터 유형으로 **"Resting Heart Rate"를 명시적으로 나열**하고, 설정 절차를 `"Open up the Shortcut. In the first step, you can change 'Type' to be whatever data you're trying to export (Heart Rate is selected by default)."`라고 원문으로 적어, 단축어의 "Find (All) Health Sample(s) where" 액션의 Type 파라미터에서 Resting Heart Rate 를 선택해 실제로 내보낸다는 것을 확인했다. 보강 근거: Health Exporter & Shortcuts 앱 App Store 페이지(원문 열람 확인, 위 URL)도 "Heart: Resting Heart Rate"를 내보내기 항목으로 명시(다만 이 앱은 자체 리더일 가능성이 있어 1차 근거로는 heartbridge 쪽이 더 직접적이다) |
| 수면단계 (Sleep stages) | **가능 (단, 파싱 필요)** | Automators Talk 포럼 스레드 "Shortcut to export Sleep Data" — 원문 열람 확인(WebFetch, <https://talk.automators.fm/t/shortcut-to-export-sleep-data/18100>). 사용자 mvan231 이 공유한 단축어("Last Night's Sleep", "Chosen Date Sleep Analysis")가 Sleep Analysis 유형의 건강 샘플을 가져와 Awake/Deep/REM/Core 개별 단계를 실제로 분리해 냈다고 확인됨. 원문이 "Sleep logs data every few minutes and the kind of data logged varies (i.e., it changes from Awake to Deep to REM to Core versions)"라고 명시 — 즉 단축어가 단계별로 미리 합산된 숫자를 주는 게 아니라 **개별 샘플(각각 시작·끝 시각 + 단계 이름 문자열)의 나열**을 주고, 이를 받는 쪽(서버·앱 코드)에서 합산·분류해야 한다. **확인 못 함**: Apple 공식 "What's new in Shortcuts" 페이지에 "Find Health Sample 액션이 이제 수면 단계(core/deep/REM)를 반환한다"는 업데이트가 있다는 검색 스니펫이 있었으나, 해당 페이지는 이 조사에서 도구가 "본문이 너무 길어 잘렸다"고 반환해 원문을 직접 확인하지 못했다 — 이 스니펫은 근거로 쓰지 않았고, 위 포럼 1차 후기만으로 판정했다 |

## 오너가 실기기(단축어 앱)에서 확인할 절차

- 활동에너지(불확실 항목) — 아이폰 단축어 앱 > 새 단축어 > "건강 샘플 찾기"(Find Health Sample) 액션 추가 > Type 을 탭해 "활동 에너지"/"Active Energy"/"Active Calories"를 검색해 선택되는지, 실행 시 오늘자 값이 실제로 반환되는지 확인한다.

(안정시심박·걸음수·수면단계는 위 표의 근거로 "가능" 판정. 다만 기기에 해당 유형의 샘플 자체가 없으면
— 예: Apple Watch 미착용으로 안정시심박이 한 번도 기록되지 않은 경우 — 액션이 지원해도 빈 결과가
나올 수 있다는 점은 공통 주의사항이다.)

## 활동 축 필드 결정 (spec.md D-G 참고용)

- **걸음수(steps)**: 채택 — 근거 확실.
- **활동에너지(active_energy_kcal)**: 채택은 보류하지 않되(마이그레이션·코드 경로는 이미 만들어짐, `write-migration-009`/`widen-health-ingest` 참고), 판정이 "불확실"이므로 **오너의 실기기 확인 전에는 이 필드가 항상 채워진다고 가정한 로직(필수값 취급 등)을 만들지 말 것** — 결측으로 흘러도 깨지지 않아야 한다.
- **안정시심박·수면단계**: 이번 스펙(D-G)의 활동 축 범위 밖. 안정시심박은 회복 축을 나중에 확장할 경우를 대비해 조사했고, 근거는 "가능"이나 이 문서 시점에서 코드 반영 계획은 없다.

## 요약

| 항목 | 판정 |
|---|---|
| 걸음수 | 가능 |
| 활동에너지 | 불확실 |
| 안정시심박 | 가능 |
| 수면단계 | 가능 (파싱 필요) |
