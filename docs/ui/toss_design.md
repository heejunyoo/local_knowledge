# Knowledge UI — Toss design philosophy (adapted)

Personal PKM UI does **not** copy TDS assets. It adopts Toss product philosophy:

## Principles

1. **본능적 단순함** — 한 화면에 한 가지 일. 녹음 / 리뷰 / 검색을 분리.
2. **숨 쉴 여백** — 8pt 그리드, 카드 간 16–24pt, 화면 가장 여백 넉넉히.
3. **명확한 위계** — 큰 제목(28–32), 본문(15–17), 보조(13) 회색.
4. **행동 중심 CTA** — Primary 파란 버튼 하나. 보조는 텍스트/회색.
5. **Quiet by Default** — 성공 토스트 남발 금지. 실패·리뷰 대기·기한만.
6. **한국어 라이팅** — 짧고 친절. 기술 용어는 필요할 때만.
7. **신뢰** — 근거(evidence)·상태·에러를 숨기지 않되, 공포 톤 금지.

## Color tokens (approx. Toss blue family)

| Token | Hex | Use |
|-------|-----|-----|
| `blue500` | `#3182F6` | Primary CTA, links, active |
| `blue50` | `#E8F3FF` | Soft highlight / badge bg |
| `grey900` | `#191F28` | Primary text |
| `grey700` | `#4E5968` | Secondary text |
| `grey500` | `#8B95A1` | Tertiary / meta |
| `grey200` | `#E5E8EB` | Dividers |
| `grey100` | `#F2F4F6` | Page / card bg |
| `grey50` | `#F9FAFB` | App chrome |
| `red500` | `#F04452` | Failure only |
| `green500` | `#03B26C` | Optional success (rare) |
| `white` | `#FFFFFF` | Cards on grey100 |

## Typography

- System SF Pro / Apple SD Gothic Neo (macOS) — Toss Product Sans 미사용 (라이선스).
- Title: **semibold 28** tracking tight  
- Section: **semibold 17**  
- Body: **regular 15** line 22  
- Caption: **regular 13** grey500  

## Components

- **Card**: white, radius 16, no heavy shadow (hairline border grey200).
- **Primary button**: blue500 fill, white text, height 48–52, radius 12.
- **Secondary**: grey100 fill, grey900 text.
- **Badge**: blue50 / blue500 text for `review_needed`; red soft for failed.
- **Menu bar**: minimal glyph + numeric badge (review + failed count).

## Microcopy (KO)

| Situation | Copy |
|-----------|------|
| Idle | 녹음할 준비가 됐어요 |
| Recording | 듣고 있어요 |
| Processing | 정리하는 중… |
| Review | 확인이 필요해요 |
| Failure | 문제가 생겼어요. 다시 시도해 주세요 |
| Empty review | 확인할 미팅이 없어요 |

## Anti-patterns

- 다크 그라데이션 히어로 / 과도한 일러스트  
- 성공마다 팝업  
- 한 화면에 설정·검색·녹음 전부  
- 기술 상태 문자열 그대로 노출 (`summarized_candidate` → "요약 검토")
