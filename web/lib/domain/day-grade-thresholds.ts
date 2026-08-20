// 하루 등급 — 임계값·등급컷.
//
// 채점 형태(rangeScore·attainmentScore·limitScore)는 day-grade.ts 에 있다. 이 파일은 그
// 함수들에 넘길 "숫자"만 담는다 — 원문으로 확인한 값만 임계값이 될 수 있다(spec.md §7).
//
// 두 종류를 분명히 가른다:
//   고정값       — 기관·연도·URL 이 있는 공식 기준. 프로필과 무관하다. DEFAULT_THRESHOLDS.
//   프로필 의존값 — 사람마다 다른 값(에너지·단백질). thresholdsFor(profile) 안에서만 계산한다.
//     이 값들은 diet-read.ts 의 recommendedKcal 등을 그대로 호출한다 — 다시 계산하지 않는다.
//
// 원문을 못 연 값은 넣지 않았다 — WHO 2023 포화지방 가이드라인(10% 미만), IOM/NIH ODS
// 단백질 DRI(0.8 g/kg) 둘 다 docs/HEALTH_STANDARDS_2026-08.md §5 에서 "확인 못 함"으로
// 명시됐다. 그 두 값은 아래 어디에도 없다.
//
// 근거: docs/HEALTH_STANDARDS_2026-08.md
//      .claude/specs/daily-grade/spec.md — D-I(단백질) · D-J(활동) · D-N(회복) · D-O(등급컷) · D-P(섭취 상한 읽기 경로)

import { recommendedKcal, type Profile } from "@/lib/domain/diet-read";
import type { GradeCuts } from "@/lib/domain/day-grade";

/** 회복(수면) 축 — 하한형. 상한 감점은 넣지 않는다(D-N). */
export interface RecoveryThresholds {
  /**
   * 수면 하한(시간). 이 미만이면 감점 대상.
   *
   * AASM(미국수면의학회)·SRS(수면연구학회) 공동합의문, 2015 — 성인(18–60세) 7시간 이상/야.
   * J Clin Sleep Med 2015;11(6):591–592, doi:10.5664/jcsm.4758
   * https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf
   *
   * 상한(예: 9h)은 의도적으로 넣지 않았다 — 같은 합의문이 9시간 초과를 "일부에는 적절할
   * 수 있으나 그 외에는 건강 위험 여부 불확실"이라고 명시해 확정 수치가 없다. 확정되지
   * 않은 값은 임계값으로 쓰지 않는다(spec.md D-N).
   */
  sleepMinHours: number;
}

/** 활동 축 — 달성률형. 최근 7일 누적 중강도 분 ÷ 목표, 상한 100(day-grade.ts attainmentScore). */
export interface ActivityThresholds {
  /**
   * 최근 7일 누적 중강도 유산소 분 목표.
   *
   * WHO, 2020 — 성인(18–64세) 중강도 유산소 150–300분/주(또는 고강도 75–150분/주, 등가 조합).
   * *WHO guidelines on physical activity and sedentary behaviour*, 2020.
   * https://www.ncbi.nlm.nih.gov/books/NBK566046/
   * 한국 질병관리청 국가건강정보포털도 동일 수치를 그대로 준용한다(기관 간 값 차이 없음).
   *
   * 150(하한)을 채택했다. 하루 단위 권장치는 원문에 없어 150÷7 같은 환산을 하지 않고
   * 7일 누적으로 채점한다(spec.md D-J). 코드의 RECOMMENDED_WEEKLY_WORKOUTS·
   * RECOMMENDED_WORKOUT_MINUTES_PER_DAY(diet-read.ts)는 활동수준별 세분화가 조사로도
   * 1차 근거를 찾지 못해 여기 쓰지 않는다.
   */
  weeklyModerateMinutesTarget: number;
}

/** 섭취 축 — 에너지·단백질은 목표형(달성률), 당·나트륨·포화지방은 상한형. */
export interface IntakeThresholds {
  /**
   * 프로필 의존. `recommendedKcal(profile)` 을 그대로 쓴다(diet-read.ts) — 이 파일에서
   * 다시 계산하지 않는다.
   */
  kcalTarget: number;

  /**
   * 프로필 의존. 체중(kg) × 0.91.
   *
   * 한국 보건복지부·한국영양학회, KDRIs 2020 — 권장섭취량(RNI) 0.91 g/kg(일반 성인,
   * 결핍 예방 기준). Journal of Nutrition and Health 2022;55(1):10.
   * https://e-jnh.org/DOIx.php?id=10.4163%2Fjnh.2022.55.1.10
   *
   * ⚠ 코드의 `recommendedProteinG`(diet-read.ts, 체중×1.6·식단 화면의 개인 목표)와는 다른
   * 값이다. 1.6 은 ISSN(국제스포츠영양학회) 2017 운동인 권장범위(1.4–2.0 g/kg)의 중앙값으로
   * 일반 인구 기준(KDRIs 0.91·IOM 0.8)의 약 2배다 — 등급 임계값으로 쓰면 평범한 날이 거의
   * 항상 미달로 찍힌다(spec.md D-I). 식단 화면 목표는 고치지 않는다. 등급은 0.91 만 쓴다.
   */
  proteinGTarget: number;

  /**
   * 고정값. 100g(2,000kcal 기준 1일영양성분기준치).
   *
   * 한국 식품의약품안전처, 「식품 등의 표시·광고에 관한 법률 시행규칙」[별표5], 2020.9.9 개정.
   * https://www.law.go.kr/LSW/flDownload.do?gubun=&flSeq=76612387&bylClsCd=110201
   *
   * WHO 2015 는 유리당을 총에너지의 10% 미만(조건부 5% 미만)으로 권고하지만 비율이라
   * kcal 없이 못 쓴다 — g 단위인 식약처 값을 상한으로 쓴다.
   */
  sugarGLimit: number;

  /**
   * 고정값. 2,000mg/일 미만.
   *
   * WHO, 2012 — *Guideline: Sodium intake for adults and children* (나트륨 2g/일 미만 ≒
   * 소금 5g/일 미만). https://www.ncbi.nlm.nih.gov/books/NBK133297/
   * 한국 식약처 라벨 기준치(2,000mg, 위 시행규칙 [별표5])도 같은 값이라 병기한다.
   * KDRIs 2020 의 만성질환위험감소섭취량(2,300mg)은 발행 성격(국내 인구 평균 개선 목표)이
   * 달라 쓰지 않는다 — WHO·식약처가 일치하는 2,000mg 을 상한으로 채택했다.
   */
  sodiumMgLimit: number;

  /**
   * 고정값. 총에너지의 7% 미만(비율 — 절대 g 이 아니다).
   *
   * 한국 보건복지부·한국영양학회, KDRIs 2020(19세 이상, 2025 개정판도 동일 값 유지) —
   * 서울시민 건강포털(서울의료원) "2025 한국인 영양소 섭취기준" 원문 확인.
   * https://health.seoulmc.or.kr/healthCareInfo/nutrientStandard.do
   *
   * WHO 2023 포화지방 가이드라인(총에너지 10% 미만 — 검색 스니펫만 있고 원문 미열람)은
   * 확인 못 해 넣지 않았다(docs/HEALTH_STANDARDS_2026-08.md §5-2). 확인되면 이 자리에 병기한다.
   */
  satFatEnergyRatio: number;
}

export interface GradeThresholds {
  recovery: RecoveryThresholds;
  activity: ActivityThresholds;
  intake: IntakeThresholds;
  /**
   * 등급 컷 — A ≥ 90 / B ≥ 75 / C ≥ 60 / D ≥ 40 (미만은 E).
   *
   * ⭐ 외부 기준 없음 — 의미 정박값이다. 점수는 "권장 대비 달성도"로 정의된다(spec.md D-D).
   * 그 정의에 A=거의 모든 축이 권장을 충족, B=대체로 충족(한 축만 조금 모자람),
   * C=절반쯤 충족, D=대부분 미달, E=거의 기록 없음/거의 미달 이라는 의미를 붙였을 뿐,
   * 임상·정책 문헌에서 가져온 컷오프가 아니다. 본인 과거 분포로 잡지도 않았다(spec.md D-O).
   */
  cuts: GradeCuts;
}

/** 고정 임계값(프로필과 무관인 부분만) — 각 필드의 출처는 위 인터페이스 주석 참고. */
export const DEFAULT_THRESHOLDS: {
  recovery: RecoveryThresholds;
  activity: ActivityThresholds;
  intake: Omit<IntakeThresholds, "kcalTarget" | "proteinGTarget">;
  cuts: GradeCuts;
} = {
  recovery: {
    sleepMinHours: 7,
  },
  activity: {
    weeklyModerateMinutesTarget: 150,
  },
  intake: {
    sugarGLimit: 100,
    sodiumMgLimit: 2000,
    satFatEnergyRatio: 0.07,
  },
  cuts: {
    cuts: [
      [90, "A"],
      [75, "B"],
      [60, "C"],
      [40, "D"],
    ],
  },
};

/**
 * KDRIs 2020 — 일반 성인 단백질 권장섭취량(RNI) 0.91 g/kg. IntakeThresholds.proteinGTarget
 * 주석 참고. 상수로 빼둔 이유는 diet-read.ts 의 1.6(운동인 기준, 식단 화면 전용)과 같은
 * 자리에서 헷갈리지 않게 하기 위해서다 — 절대 1.6 을 여기로 끌어오지 않는다.
 */
const PROTEIN_G_PER_KG_RNI = 0.91;

/**
 * 프로필 의존 임계값까지 채운 GradeThresholds 를 돌려준다.
 * kcalTarget·proteinGTarget 은 profile 마다 다르다 — 그 외는 DEFAULT_THRESHOLDS 그대로다.
 */
export function thresholdsFor(profile: Profile): GradeThresholds {
  return {
    recovery: DEFAULT_THRESHOLDS.recovery,
    activity: DEFAULT_THRESHOLDS.activity,
    intake: {
      ...DEFAULT_THRESHOLDS.intake,
      kcalTarget: recommendedKcal(profile),
      proteinGTarget: round1(profile.weightKg * PROTEIN_G_PER_KG_RNI),
    },
    cuts: DEFAULT_THRESHOLDS.cuts,
  };
}

/** 지방 1g ≈ 9kcal — 영양학에서 통용되는 Atwater 계수. 비율→그램 환산에만 쓴다. 이 상수
 * 자체는 이번 조사 대상(§ D-I·D-J·D-N·D-O·D-P)이 아니다 — 정책 임계값이 아니라 단위 변환값이다. */
const KCAL_PER_G_FAT = 9;

/**
 * 포화지방 상한은 비율(그날 kcal 의 7%)이라 절대 g 로 쓰려면 그날 kcal 이 있어야 한다.
 * kcal 이 없거나 0이면 분모가 없다 — null 을 돌려준다. 호출부는 이 하위항목만 결측으로
 * 다루고, 0으로 나누지 않는다(spec.md D-P).
 */
export function satFatLimitG(
  kcalForDay: number | null | undefined,
  thresholds: GradeThresholds,
): number | null {
  if (kcalForDay === null || kcalForDay === undefined || kcalForDay === 0) return null;
  return (kcalForDay * thresholds.intake.satFatEnergyRatio) / KCAL_PER_G_FAT;
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
