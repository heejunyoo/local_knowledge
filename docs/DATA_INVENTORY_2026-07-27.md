# 데이터 인벤토리 동결 — 2026-07-27 (P0-3)

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` P0-3 실행 산출물.
> 아래 수치는 **직접 쿼리·직접 스캔**한 결과다. 방향성/액션플랜 문서의 기재 수치와 다른 항목은 **실측값을 우선**하고 차이를 명시한다.

## 1. SQLite 행수 (`~/Knowledge/index/knowledge.db`, 백업본과 동일 시점)

```
knowledge_unit      243
knowledge_chunk     621
note_mirror          19
source_pointer      243
connected_source      4
fts_docs            243
chunk_vector        621
meeting               0
action_item           0
pipeline_events       0
```
→ 액션플랜 §7 기재치와 **정확히 일치**. 데이터 드리프트 없음.

`connected_source` 상세 (C-4의 "vault 루트 2개" 구조 확인):
| id | source_type | root_path | unit_count(캐시값) |
|---|---|---|---|
| `src:meeting` | meeting | `~/Knowledge` | 0 |
| `src:obsidian-default` | obsidian | `~/Obsidian/Main` | 224 |
| `src:notes` | notes | (Notes 앱) | 19 |
| `src:folder:ca0da96e...` | obsidian | iCloud `heejun_pkm/heejun_PKM` | 224 |

## 2. ★ C-4 vault ↔ 인덱스 대사 (실측 — **액션플랜 C-1 표 대비 정정**)

**방법**: iCloud vault(`heejun_pkm/heejun_PKM`) + `~/Obsidian/Main/Meetings` 파일 목록을 유니코드 **NFC 정규화** 후 `knowledge_unit.sot_ref`(source_type='obsidian', NFC 정규화)와 집합 비교. (macOS APFS는 파일명을 NFD로 반환하므로 정규화 없이 비교하면 전량 불일치가 발생함 — C-4/P2-2가 지적한 정규화 이슈가 실제로 재현됨.)

```
vault1 (iCloud heejun_pkm/heejun_PKM) md 파일     225개  ← Meetings/2026/07/dogfood-*.md 4개 포함
vault2 (~/Obsidian/Main/Meetings)     md 파일       3개
combined unique                                  228개
knowledge_unit(obsidian) 인덱스 행                224개  (Meetings/ 접두 7건 포함)
```

| 구분 | 건수 | 내역 |
|---|---|---|
| **양쪽 일치** | 224 | 인덱스 224건 전부 실파일 존재 |
| **인덱스에만 있음 (stale)** | **0** | — |
| **파일에만 있음 (미인덱스)** | **4** | 아래 목록 |

미인덱스 4건 (전부 `20 💎 핵심지식`/`10 📥 수집함` 일반 노트, 미팅 무관):
```
10 📥 수집함/RAG 파이프라인.md
20 💎 핵심지식 (💡 내생각)/MOC - 학습 - 문제해결, 리서치 - 문제해결.md
20 💎 핵심지식 (💡 내생각)/리서치 구조화 - 어디서 찾을것인가.md
20 💎 핵심지식 (💡 내생각)/프론트엔드 학습의 기본 개념 정립.md
```

`Meetings/` 접두 인덱스 7건 실측 (F-1 아카이브 대상):
```
Meetings/2026/07/18D735A0-...md        → 실파일 존재 (~/Obsidian/Main/Meetings)
Meetings/2026/07/7A4A54BD-...md        → 실파일 존재 (~/Obsidian/Main/Meetings)
Meetings/2026/07/C6CBC33B-...md        → 실파일 존재 (~/Obsidian/Main/Meetings)
Meetings/2026/07/dogfood-1783605637.md → 실파일 존재 (iCloud vault 자체 Meetings/ 하위)
Meetings/2026/07/dogfood-1783605657.md → 실파일 존재 (iCloud vault 자체 Meetings/ 하위)
Meetings/2026/07/dogfood-1783647810.md → 실파일 존재 (iCloud vault 자체 Meetings/ 하위)
Meetings/2026/07/dogfood-1783648014.md → 실파일 존재 (iCloud vault 자체 Meetings/ 하위)
```

**⚠️ 액션플랜 C-1/C-4 정정 사항**: 문서는 "`Meetings/` 인덱스 7건 중 파일 실존 3건 → 4건 stale, vault md 225 vs 인덱스 217 → 불일치 8건"이라고 기재했으나, **실측 결과 stale 0건 / 미인덱스 4건 / 불일치 총 4건**이다. 원인은 (a) iCloud vault 자체에 문서 작성 시점 이후(또는 미인지 상태로) `Meetings/` 서브폴더가 이미 존재했고 dogfood 테스트 파일 4건이 그 안에 실존했으며, (b) 정규화 없이 비교하면 전량이 불일치로 잘못 잡히는 문제가 있었기 때문이다. **P1 이관 목표 행수는 이 문서의 실측치를 기준으로 한다.**

### P1 이관 목표 행수 (확정)
```
vault_md 이관 대상  = 224(현재 인덱스, obsidian) − 7(Meetings, F-1 제외) + 4(신규 미인덱스) = 221
notes_app           = 19  (note_mirror 그대로)
knowledge_chunk     = 621 전량 마이그레이션 대상이나, Meetings 소속 chunk는 제외 후 재계산 필요 (P1에서 unit_id 기준 필터링)
diet_meal / workout / metric = 25 / 8 / 8
inbox_item          = 2 (전부 promoted)
```

## 3. Vault 구성 (실측 — 크기 **정정**)

```
iCloud vault (heejun_pkm/heejun_PKM)  총 29M  (액션플랜 기재 "6.8MB"와 불일치 — 첨부파일 포함 실측치로 정정)
  md 파일        225개
  비-md 파일      35개 (첨부파일 34 + 최상위 2 + .DS_Store 1, 아래 상세)
```

비-md 파일 상세:
| 파일 | 종류 | 처리 |
|---|---|---|
| `CyberSourceKey_20250918223005.pem` | RSA/EC 개인키로 추정 | **완료 — `~/Secrets/`로 이동, vault에는 참조 노트만 남김 (P0-5)** |
| `postmanv2.html` | HTML | **완료 — 확인 결과 정적 Postman 클론 도구, 비밀정보 없음. 조치 불필요 (P0-5)** |
| `90 ⚙️ 첨부파일/*.png`, `*.gif` (30개) | 이미지 | 그대로 유지 (스크린샷/프리뷰) |
| `90 ⚙️ 첨부파일/Heejun_PaySlip_2410_2503.pdf` | **급여명세서 (개인 금융정보)** | **미해결 — P2 착수 전 오너 재검토 필요 (아래 참고)** |
| `90 ⚙️ 첨부파일/유희준_재직증명서(유이현).pdf` | **재직증명서 (개인정보)** | **미해결 — P2 착수 전 오너 재검토 필요** |
| `90 ⚙️ 첨부파일/Congratulations_on_your_Visa_Offer_Heejun_Yo.pdf` | **비자 오퍼 레터 (개인정보)** | **미해결 — P2 착수 전 오너 재검토 필요** |
| `90 ⚙️ 첨부파일/AD_4nX*.png` (2개) | 이미지(외부 저장 서비스 자동 명명) | 그대로 유지 |
| `.DS_Store` | macOS 메타 | 무시 대상 |

> **추가 발견 (액션플랜 C-5에 없던 항목)**:
> 1. PII/금융 PDF 3건(급여명세서·재직증명서·비자 오퍼)은 "비밀정보"(API 키 등)는 아니지만 개인 식별/금융 정보이므로, P2에서 vault를 Git 프라이빗 레포에 올릴 때 동일 수준의 주의가 필요하다. G0-3 게이트(`.pem/.p12/.key`) 스코프 밖이라 P0-5에서는 이동하지 않았다. **P2-1 착수 전 오너가 유지/제외를 결정해야 한다.**
> 2. `95 🗑️ 아카이브/2022/토페업무/` 하위 md 노트 2건에 **실제 값이 박힌 결제 시크릿**(라이브 API 키, 결제 세션 시크릿 4건)이 평문으로 존재했다. 오너 확인 후 값만 `[REDACTED]`로 치환 완료(2026-07-27). 상세는 `docs/ENV_VARS.md` "격리 조치 기록" 참조.

## 4. JSON 서비스 데이터

```
diet.json   meals 25 / workouts 8 / metrics 8 / goals 1(존재) / profile 1(존재)
inbox.json  items 2 (전부 status=promoted)
```
→ 액션플랜 §7 기재치와 일치.

## 5. Config

```
~/Knowledge/config/
  app.json  features.json  llm_providers.json  tools_manifest.json
  mobile_devices.json (0600)  secrets.json (0600)  redaction_patterns.json
```
→ 키 이름 목록은 P0-5에서 `docs/ENV_VARS.md`로 별도 기록 (값 제외).

## 6. Tools

```
~/Knowledge/tools/  4.4G  ← P7에서 삭제 예정, 변경 없음
```

## 7. 백업 (P0-2 산출물)

```
~/Knowledge-backup-2026-07-27/  (읽기전용, chmod a-w 적용됨)
  knowledge.db, services/, config/, vault/(iCloud vault 미러)
  CHECKSUMS.txt — shasum -a 256 -c 로 검증 완료 (전체 PASS)
```

## 8. 쓰기 동결 (P0-8) — 되돌리기 정보

```
동결 커밋 SHA: f2061ee7f81e1dd3f304fda10f3376608899e5e1
브랜치: refactor/web-p0
```

동결 시점(2026-07-27) 해시:
```
1ce6f78be895005b150f52dbfb50ea258d5162905bada2d385389d2b105ce41a  ~/Knowledge/index/knowledge.db
87e444e7e6485f19b8d8b444e67a5696dd902a0c3a8a5b834b07de15082cbf28  ~/Knowledge/services/diet/diet.json
473bf5840f243a5a4e31ceeef741ead4f76e1b4f443b03381cec1ce06a0fc8ca  ~/Knowledge/services/inbox/inbox.json
```
→ P1 착수 시점에 재계산해 동일한지 확인 (G1-6).

**실측 추가 발견**: 문서 P0-8 초안은 `MobileHTTPServer.swift`의 `handleRPC`(JSON-RPC 디스패치) 진입부만 동결 대상으로 명시했으나, 실측 결과 `/v1/chat`(자연어 채팅) 경로의 `handleDietChat`이 `diet.logWorkout`/`diet.logMeal`을 **`handleRPC`를 거치지 않고 직접 호출**하고 있어 최초 가드만으로는 우회 가능했다. 같은 커밋에서 `handleDietChat`의 두 쓰기 분기에도 동일 가드를 추가해 막았다 (G0-4에서 `/v1/chat` 경로까지 실제 curl로 검증 완료).

---
*이 문서는 P0 시점에 동결된다. 이후 수치가 바뀌면(재채취 등) 이 문서가 아니라 신규 날짜의 문서를 만든다.*
