# 하루 등급 — 외부 공중보건 기준 조사

작성 2026-08-20 · Sonnet 5 · `research-health-standards` (phase p1-standards)
**목적: `.claude/specs/daily-grade/spec.md` §6 의 임계값 원문 조사. 채점 로직은 범위 밖이다.**
모든 항목은 원문을 실제로 열어(WebFetch/PDF Read) 확인했다 — 검색 스니펫만으로 채운 항목은 없다.
단, 일부 항목은 PDF 렌더링 실패 등으로 원문 표를 직접 못 열었고 그 경우 §5 에 명시한다.

---

## 1. 수면시간 (회복 축 — 범위형)

| 기관 | 연도 | 값 | 원문 |
|---|---|---|---|
| AASM(미국수면의학회) · SRS(수면연구학회) 공동합의문 | 2015 | **성인(18–60세) 7시간 이상/야**. 9시간 초과는 "일부(젊은 성인·수면부채 회복 중·질병 회복기)에는 적절할 수 있으나 그 외에는 건강 위험 여부 불확실" — 상한을 확정 값으로 제시하지 않음 | J Clin Sleep Med 2015;11(6):591–592, doi:10.5664/jcsm.4758 — PDF 원문을 직접 열어 확인 (<https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf>) |
| CDC (미국 질병통제예방센터) | 2016 | 위 AASM/SRS 합의문을 그대로 채택·인용 (MMWR 2016;65(6):137–141) | CDC 페이지는 403 으로 직접 열람 실패 — AASM/SRS 원문(위)으로 대체 확인 |
| 한국 (보건복지부·질병관리청) | — | **독자 기준 없음.** 한국인 영양소 섭취기준(KDRIs)은 영양소만 다루고 수면시간은 포함하지 않는다(검색 결과 확인). 국내 의료계는 AASM/SRS·CDC 기준을 그대로 준용하는 것으로 보이나, 이를 명시한 정부 발행 원문은 찾지 못함 | 확인 못 함 |

**채택 제안**: 범위형 채점이므로 하한만 있는 CDC/AASM 값(7h+)으로는 "너무 많이 자도 감점"을 구현할 수 없다. 상한은 원문에 확정 수치가 없으므로, 실무 관행상 통용되는 "7–9시간"(AASM/SRS 합의문 본문의 하한 7h + 통상 인용되는 상한 9h)을 잠정 범위로 쓰되, **9h 상한 자체는 합의문이 "불확실"이라고 명시한 값**이라는 점을 규칙 주석에 남겨야 한다. 이 판단은 §6 범위 밖(채점 설계)이라 여기 기록만 하고 결정하지 않는다.

## 2. 주간 신체활동 (활동 축 — 달성률형)

| 기관 | 연도 | 값 | 원문 |
|---|---|---|---|
| WHO | 2020 | 성인(18–64세) **중강도 유산소 150–300분/주** 또는 **고강도 75–150분/주** 또는 등가 조합. 근력운동 주 2회 이상(모든 주요 근육군) | *WHO guidelines on physical activity and sedentary behaviour*, 2020 — NCBI Bookshelf 원문 열람 확인 (<https://www.ncbi.nlm.nih.gov/books/NBK566046/>) |
| 한국 질병관리청 (국가건강정보포털) | — (페이지 상시 갱신, 연도 표기 없음) | **동일**: 중등도 이상 유산소 150–300분/주 또는 고강도 75–150분/주, 근력운동 주 2회 이상 | 국가건강정보포털 "운동" 페이지 원문 열람 확인 (<https://health.kdca.go.kr/healthinfo/biz/health/gnrlzHealthInfo/gnrlzHealthInfo/gnrlzHealthInfoView.do?cntnts_sn=5293>) — WHO 2020 권고를 그대로 준용 |

기관 간 값 차이 없음 — WHO 값을 그대로 쓰면 된다. 코드의 `RECOMMENDED_WEEKLY_WORKOUTS`(활동수준별 3~5회)·`RECOMMENDED_WORKOUT_MINUTES_PER_DAY`(20~45분)는 이 150~300분/주 범위와 방향은 맞지만 **활동수준(activity)별 세분화·일일 분배 방식은 WHO/KDCA 원문에 없는 자체 설계**다 — 출처 없음, §5 참고.

## 3. 당·나트륨·포화지방 일일 상한 (섭취 축 — 상한 초과 시 감점)

| 영양소 | 기관 | 연도 | 값 | 원문 |
|---|---|---|---|---|
| 유리당(free sugars) | WHO | 2015 | 총에너지의 **10% 미만**(강한 권고), **5% 미만**이면 추가 이익(조건부 권고) | *Guideline: Sugars intake for adults and children*, WHO-NMH-NHD-15.3 — 원문 열람 확인 (<https://www.who.int/publications/i/item/WHO-NMH-NHD-15.3>) |
| 당류 | 한국 식약처 (법정 라벨 기준치) | 2020.9.9 개정 | **100g**(2,000kcal 기준 1일영양성분기준치) | 「식품 등의 표시·광고에 관한 법률 시행규칙」[별표5] — PDF 원문을 직접 열어 표 전체 확인 (<https://www.law.go.kr/LSW/flDownload.do?gubun=&flSeq=76612387&bylClsCd=110201>) |
| 나트륨 | WHO | 2012 | **2g/일 미만**(=소금 5g/일 미만, 강한 권고) | *Guideline: Sodium intake for adults and children* — NCBI Bookshelf executive summary 원문 열람 확인 (<https://www.ncbi.nlm.nih.gov/books/NBK133297/>) |
| 나트륨 | 한국 보건복지부·한국영양학회 (KDRIs) | 2020 | **만성질환위험감소섭취량 2,300mg/일** | 2020 KDRIs 제·개정 리뷰 논문(Journal of Nutrition and Health 2021;54(5):425) 원문 열람 확인 (<https://e-jnh.org/DOIx.php?id=10.4163%2Fjnh.2021.54.5.425>) — 저자가 KDRIs 제정위원(한국영양학회), 이해당사자 아님 |
| 나트륨 | 한국 식약처 (법정 라벨 기준치) | 2020.9.9 개정 | **2,000mg**(2,000kcal 기준) | 위와 동일 법령 PDF 원문 (<https://www.law.go.kr/LSW/flDownload.do?gubun=&flSeq=76612387&bylClsCd=110201>) |
| 포화지방 | WHO | 2023 (최신 개정 가이드라인) | 총에너지의 **10% 미만** — 이번 조사에서 WHO 2023 saturated fat 가이드라인 원문은 열지 못함, 검색 스니펫만 확인됨 | **확인 못 함** — 원문 미열람이므로 사용 보류 |
| 포화지방 | 한국 보건복지부·한국영양학회 (KDRIs, 19세 이상) | 2015/2020(동일 값 유지, 2025 개정판도 동일) | 총에너지의 **7% 미만** | 서울시민 건강포털(서울의료원, 지자체 공공보건기관) "2025 한국인 영양소 섭취기준" 표 원문 열람 확인 (<https://health.seoulmc.or.kr/healthCareInfo/nutrientStandard.do>) — 19세 이상 "7 미만"(%) 명시 |
| 포화지방 | 한국 식약처 (법정 라벨 기준치) | 2020.9.9 개정 | **15g**(2,000kcal 기준) | 위와 동일 법령 PDF 원문 |

**메모**: 식약처 "1일영양성분기준치"는 원래 가공식품 %영양성분기준치 표시용 참조값(2,000kcal 기준 인구집단 평균)이지 임상적 "상한선" 그 자체는 아니다. 다만 실무에서 상한 목표치로 널리 쓰이고, g/mg 절대값이라 하루 등급 채점에 바로 대입 가능하다는 실용적 이점이 있다. KDRIs 나트륨 값(2,300mg)과 식약처 라벨 값(2,000mg)은 발행기관·근거(전자는 심혈관질환 위험 메타분석, 후자는 라벨 표시용 반올림 참조치)가 달라 값이 다르다.

**채택 제안** (근거와 함께, 실제 채점 설계는 이후 세션 몫):
- **당류**: WHO 10%(더 엄격 5%)는 g 단위가 아니라 에너지 비율이라 `kcal` 필드 없이 바로 채점하기 어렵다. 반면 식약처 100g 은 절대값이라 즉시 쓸 수 있다 → **식약처 100g 을 상한으로, WHO 10%/5% 원칙은 주석으로 병기** 권고.
- **나트륨**: KDRIs 2,300mg(만성질환 위험감소, 국내 최신 영양학 근거) vs 식약처 2,000mg(라벨용) vs WHO 2,000mg(국제 권고, 심혈관질환 근거) — **WHO 값과 식약처 값이 2,000mg 으로 일치**하므로 이 값을 상한으로 쓰고, KDRIs 2,300mg 은 "이 이상이면 즉시 위험" 이 아니라 "국내 인구 평균 개선 목표"라는 성격 차이를 주석에 남길 것을 권고.
- **포화지방**: WHO 최신 수치를 원문으로 확인 못 했으므로, **KDRIs 7% 미만(19세 이상, 확인됨)** 을 1차 근거로 쓰고 WHO 값은 확인 후 병기 권고. 식약처 15g 은 참고용 절대값.

## 4. 단백질 권장 섭취량 (섭취 축 — 목표형) — 코드의 `체중×1.6` 검증

| 기관 | 연도 | 값 | 성격 | 원문 |
|---|---|---|---|---|
| 미국 IOM(현 NAM)/WHO 공동 채택 DRI | 2005 / 2007 | **0.8 g/kg 체중/일** (EAR 0.66, RDA 0.83→반올림 0.8) | 일반 성인 최소 권장량(97–98% 인구 결핍 예방 기준) | Institute of Medicine DRI 보고서 — 검색 스니펫만 확인, ODS(NIH) 원문 페이지는 403 으로 직접 열람 실패. **확인 못 함(2차 근거로만 취급)** |
| 한국 보건복지부·한국영양학회 (KDRIs 2020) | 2020 | 평균필요량(EAR) **0.73 g/kg**, 권장섭취량(RNI) **0.91 g/kg** | 일반 성인 결핍 예방 기준(질소평형 0.66g/kg × 이용효율 90% 보정) | Journal of Nutrition and Health 2022;55(1):10 (2020 단백질 섭취기준 리뷰, 한국영양학회 저자) — 원문 열람 확인 (<https://e-jnh.org/DOIx.php?id=10.4163%2Fjnh.2022.55.1.10>) |
| ISSN(국제스포츠영양학회) Position Stand | 2017 | **1.4–2.0 g/kg/일** (근육량 유지/증가, 운동하는 사람 대상). 저열량기 근손실 방지 목적이면 2.3–3.1 g/kg | 운동선수·활동적 인구 대상 — 결핍 예방이 아니라 근단백질 합성 최적화 목적 | *J Int Soc Sports Nutr* 2017;14:20 — PMC 원문 열람 확인 (<https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/>) |

**`recommendedProteinG` = 체중×1.6 검증 결과**:
- **일반 인구 결핍 예방 기준(IOM 0.8, KDRIs 0.91)의 약 1.8~2.2배** — 이 두 기관 기준으로는 근거 없음.
- **ISSN 스포츠영양 권장범위(1.4–2.0 g/kg, 운동하는 성인 대상)에는 포함된다** — `1.6` 이 이 범위의 중간값과 정확히 일치하는 점에서, 원 개발자가 이 범위를 참고했을 가능성이 높으나 **코드에 출처 주석이 없어 확정할 수 없다.**
- 결론: `matches_code_1_6` = **일반 인구 기준과는 불일치, 운동 인구(ISSN) 기준과는 일치** — 이 앱은 활동적 사용자(운동 축을 앱의 3대 축 중 하나로 다룸)를 전제하므로 ISSN 근거가 맥락상 더 맞을 수 있으나, **이것은 추정이지 코드에서 확인된 사실이 아니다.**

## 5. 확인 못 한 것 (검증 실패·원문 미열람)

1. **한국의 자체 성인 수면시간 권장 기준** — KDRIs 는 영양소만 다뤄 대상 외. 정부(질병관리청) 발행 수면시간 권장 원문을 찾지 못함. AASM/SRS 국제 기준 준용을 시사하는 3차 자료(언론·병원 블로그)만 있고 1차 정부 문서는 미확인.
2. **WHO 포화지방 최신(2023) 가이드라인 원문** — `https://www.who.int` 해당 페이지에 직접 접근하지 못했다. 검색 스니펫(10% 미만)만 있고 원문 열람 실패 → 사용 보류.
3. **IOM/NIH ODS 단백질 DRI 원문(0.8 g/kg)** — `ods.od.nih.gov` 페이지가 403 반환. 여러 2차 학술 출처(MDPI 리뷰 등)가 일관되게 인용하는 값이라 신뢰도는 높지만, 1차 문서를 직접 열지 못했다.
4. **CDC 수면 페이지 원문** — `cdc.gov/sleep/*` 이 403 반환. 동일 내용을 담은 AASM/SRS 1차 합의문(§1)으로 대체 확인했다.
5. **KDRIs 2020 원본 PDF(보건복지부 40MB 원문 자료집)** — 직접 렌더링하지 못했다(환경에 PDF 렌더러 `poppler` 미설치, 설치 시 기존 `pdf2image` 와 충돌 경고가 떠서 리포 범위 밖 시스템 변경으로 판단해 중단). 대신 한국영양학회 저자들이 쓴 동료 심사 리뷰 논문(Journal of Nutrition and Health, e-jnh.org)들로 개별 수치를 교차 확인했다 — 이 저널은 이해당사자(업계·판매사) 아님, KDRIs 제정 주체인 한국영양학회의 학회지.
6. **iOS 단축어의 HealthKit 실제 내보내기 가능 항목(걸음수·활동에너지·안정시심박·수면단계)** — 이번 태스크 패킷의 objective/done_when 범위 밖(§6-2 는 spec.md 원본에 있으나 이 작업 패킷의 `objective`·`done_when`은 영양·활동·수면·단백질 수치만 요구했다). 조사하지 않았다.
7. **2020 KDRIs 포화지방산 표의 1차 정부 원문(mohw.go.kr PDF)** — 열지 못함. 대신 서울의료원(공공 지자체 보건기관, 2025년판 KDRIs 인용) 웹페이지 표를 원문으로 열어 확인했다(§3).

## 6. 코드 위치 참고 (읽기만 함, 수정 안 함)

`web/lib/domain/diet-read.ts`
- L427-429 `recommendedProteinG` = `weightKg × 1.6`
- L431-437 `RECOMMENDED_WEEKLY_WORKOUTS`(활동수준별 3~5회), `RECOMMENDED_WORKOUT_MINUTES_PER_DAY`(20~45분) — 출처 주석 없음, 이번 조사로도 1차 매칭 기준을 찾지 못함(§3 WHO/KDCA 는 활동수준 세분화 없이 150–300분/주 단일 범위만 제시)

## 7. iOS 단축어 HealthKit 내보내기

작성 2026-08-20 · Sonnet 5 · `research-shortcuts-healthkit` (phase p1-standards)
**목적**: 활동 축(§3 참고)에 걸음수·활동에너지 같은 하위 항목을 붙이려면(spec.md D-G) 단축어 앱이 HealthKit
에서 실제로 무엇을 꺼낼 수 있는지부터 확인해야 한다. 리포에 네이티브 HealthKit 리더가 없다는 것은 선행
조사(§6-2 각주, `DAILY_GRADE_AND_IA_2026-08.md` §8)에서 이미 확인됐다 — 유일한 경로는 단축어의
"건강 샘플 가져오기"(Find/Get Health Samples) 류 액션이다.

**조사 방법의 한계부터 적는다**: Apple 공식 문서(`support.apple.com/guide/shortcuts/...`)는 이 액션의
Type(유형) 드롭다운에 어떤 항목이 있는지 **고정된 목록으로 게시하지 않는다** — 이 조사에서 관련
Apple 공식 가이드 페이지 여러 개를 직접 열었으나("About actions in complicated shortcuts" 등) 모두
액션 자체의 UI 설명일 뿐 유형 목록은 없었다. 이는 그 드롭다운이 Health 앱의 "탐색" 탭과 같은 HealthKit
유형 카탈로그를 그 자리에서 동적으로 끌어오는 구조이기 때문으로 보인다(카탈로그를 그때그때 검색하는
UI라 정적 문서로 나열할 이유가 없다) — **이 문장 자체는 이번 조사에서 원문으로 확인한 사실이 아니라
정황상 추정**이며, 그렇게 표시해 둔다. 결과적으로 이 절의 판정은 apple.com 1차 문서가 아니라 **실제로
그 액션을 만들어 값을 받아본 사용자들의 1차 후기(직접 연 페이지)** 에 근거한다 — objective 가 요구하는
"근거(원문 URL 또는 확인 방법)"의 성격이 §1~§6(공중보건 기관 원문)과 다르다는 점을 명시한다.

| 항목 | 판정 | 근거 |
|---|---|---|
| 걸음수 (Steps) | **가능** | Maxime Heckel, *Using Shortcuts and serverless to build a personal Apple Health API* — 원문 열람 확인 (<https://blog.maximeheckel.com/posts/build-personal-health-api-shortcuts-serverless/>). 저자가 단축어의 "건강 샘플 가져오기" 액션으로 Steps 를 실제로 가져와 "Steps measurements are grouped by hour"로 확인했고, 그 값을 JSON(`steps.count`/`steps.date`, `\n` 구분 텍스트)으로 서버리스 함수에 전송하는 전체 흐름을 직접 구현·공개했다. 같은 글에서 Heart Rate 도 동일 방식으로 가져온 것을 확인(단, Resting Heart Rate 는 아님 — 아래 참고) |
| 활동에너지 (Active Energy) | **불확실** | 이 조사에서 직접 연 1차 후기 중 "Active Energy를 건강 샘플 가져오기로 꺼냈다"를 명시한 페이지는 없었다. 정황 근거는 있음: RoutineHub 에 "Active Energy"라는 이름의 단축어가 존재(<https://routinehub.co/shortcut/1480/> — 열람 시도 시 403 으로 원문 직접 확인 실패)하고, 검색 결과 스니펫(원문 미열람)은 "Find Health Samples action in Shortcuts filtered for Active Calories"라 언급함. Health Exporter & Shortcuts 앱의 App Store 설명(원문 열람 확인, <https://apps.apple.com/no/app/health-exporter-shortcuts/id6759006922>)은 "Active Calories"를 Activity 카테고리 내보내기 항목으로 명시하지만, 이 앱이 단축어의 네이티브 "건강 샘플 가져오기" 액션을 쓰는지 자체 HealthKit 리더를 쓰고 단축어는 트리거로만 쓰는지는 설명만으로 구분 불가. Steps 와 Active Energy 는 Health 앱에서 같은 "활동(Activity)" 카테고리에 속하는 표준 HealthKit 수량 유형이라는 점에서 가능성은 높아 보이나, 이는 추정이지 이번 조사로 직접 확인한 사실이 아니다 |
| 안정시심박 (Resting Heart Rate) | **불확실** | 이 조사에서 직접 연 페이지 중 "Resting Heart Rate"를 명시적으로 건강 샘플 가져오기 액션에서 선택해 값을 받은 사례를 확인한 것은 없다. 확인된 것은 (a) 일반 "Heart Rate"(안정시 아님)를 같은 방식으로 가져온 사례(Maxime Heckel, 위 URL) (b) intervals.icu 포럼(<https://forum.intervals.icu/t/getting-wellness-data-from-your-apple-watch-via-apple-shortcuts/86164> — 원문 열람 확인)에서 사용자가 "Find Health Samples 로 원하는 데이터를 가져올 수 있다"고만 언급하고 구체 유형은 스크린샷에만 있어 텍스트로 확인 불가 (c) Health Exporter & Shortcuts 앱 설명(위 URL, 원문 열람 확인)이 "Resting Heart Rate"를 Heart 카테고리 항목으로 명시 — 다만 (b)와 동일하게 앱의 내보내기 경로가 단축어 네이티브 액션인지는 불명확 |
| 수면단계 (Sleep stages) | **가능 (단, 파싱 필요)** | Automators Talk 포럼 "Shortcut to export Sleep Data" 스레드 — 원문 열람 확인 (<https://talk.automators.fm/t/shortcut-to-export-sleep-data/18100>). 사용자 mvan231 이 공유한 단축어("Last Night's Sleep", "Chosen Date Sleep Analysis")가 Sleep Analysis 유형의 건강 샘플을 가져와 Awake/Deep/REM/Core 개별 단계를 실제로 분리해 냈다고 확인됨. 단, 원문이 "수면은 몇 분 단위로 기록되고 단계가 계속 바뀌어 복잡하다", "텍스트 매칭으로 각 값을 분리하는 게 복잡했다"고 명시 — 단축어가 단계별로 미리 집계된 필드를 주는 게 아니라 **개별 샘플(각각 시작·끝 시각 + 단계 이름 문자열)의 나열**을 주고, 이걸 앱/서버 쪽에서 합산·분류해야 한다는 뜻으로 읽힌다 |

**오너가 실기기에서 확인할 절차** (판정이 불확실한 두 항목):
1. 활동에너지 — 아이폰 단축어 앱 > 새 단축어 > "건강 샘플 가져오기"(또는 "건강 표본 찾기") 액션 추가 > 유형(Type) 을 탭해 "활동 에너지"/"Active Energy"를 검색해 선택되는지, 실행 시 오늘자 값이 실제로 반환되는지 확인한다.
2. 안정시심박 — 같은 액션의 유형 목록에서 "안정 시 심박수"/"Resting Heart Rate"를 검색해 선택되는지, Apple Watch 로 최근 측정된 값이 있는 날짜에 실제로 반환되는지 확인한다(단축어 자체가 유형을 지원해도 기기에 그 유형의 샘플이 없으면 빈 결과가 나올 수 있어 두 가지를 구분해야 한다).

**§6 변경 지점 표(코드 변경, Phase 4)에 참고**: `web/lib/health-ingest.ts`가 향후 `steps`·`active_energy_kcal`을 수용하도록 확장될 예정이나(위 §1의 `DAILY_GRADE_AND_IA_2026-08.md` §4 표), 이 절의 판정상 걸음수는 근거가 충분하고 활동에너지·안정시심박은 오너의 실기기 확인이 선행돼야 안전하다. 수면단계는 D-G(활동 축은 운동 분만으로 시작)의 범위 밖(수면은 회복 축)이라 이번 스펙의 활동 축 하위 항목에는 직접 관련이 없지만, 회복 축을 나중에 수면단계까지 세분화할 경우를 대비해 함께 조사했다.
