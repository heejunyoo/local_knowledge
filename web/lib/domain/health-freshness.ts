// 건강 데이터 유입 신선도 — "들어오고 있는가"를 판정한다.
//
// 왜 있나: 유입 경로가 iOS 단축어 자동화 하나뿐이라 그게 죽어도 화면은 아무 말도
// 하지 않는다. 실제로 2026-07-12 이후 41일간 한 건도 안 들어왔는데 아무도 몰랐다
// (2026-08-22 확인). 등급은 결측 축을 분모에서 빼는 재정규화(D-A)를 하므로 유입이
// 끊겨도 등급이 계속 나온다 — 조용한 실패가 구조적으로 보이지 않는다.
//
// 이 파일은 시계·DB를 모르는 순수 판정만 한다. 마지막 유입 시각은 호출부가 넘긴다.
//
// ⚠ 임계값의 성격: 여기 숫자는 건강 기준이 아니라 **운영 기준**이다. 그래서
//    day-grade-thresholds.ts 와 달리 기관 원문이 없다 — 근거는 자동화 주기다.
//    docs/HEALTH_INGEST_SHORTCUT.md 가 정한 단축어 자동화는 하루 2회(기상 후·자정 전)
//    이므로, 36시간은 "연속 2회 이상 실패"를 뜻한다. 7일은 그 상태가 일주일 이어진
//    것으로, 사용자가 눈치채지 못한 채 등급이 계속 매겨지고 있었다는 뜻이다.

/** 자동화 주기(하루 2회) 기준 연속 2회 실패 = 36시간. */
export const STALE_AFTER_HOURS = 36;
/** 36시간 상태가 일주일 이어지면 "설정이 깨졌다"로 본다. */
export const BROKEN_AFTER_HOURS = 24 * 7;

export type FreshnessState =
  /** 자동화가 도는 중 */
  | "fresh"
  /** 연속 실패 의심 */
  | "stale"
  /** 설정이 깨졌다고 봐야 하는 상태 */
  | "broken"
  /** 이 채널로 한 번도 들어온 적 없음 */
  | "never";

export type ChannelId = "sleep" | "steps" | "active_energy" | "weight" | "workout";

export interface ChannelLastSeen {
  id: ChannelId;
  /** 마지막 유입 ISO 시각. 이력이 없으면 null. */
  lastTs: string | null;
}

export interface ChannelFreshness extends ChannelLastSeen {
  label: string;
  ageHours: number | null;
  state: FreshnessState;
  /** 전체 상태 판정에 넣는 채널인가 — 아래 MONITORED 참고. */
  monitored: boolean;
}

export interface HealthFreshness {
  /** 감시 채널 중 최악. 감시 채널이 하나도 없으면 "never". */
  state: FreshnessState;
  /** 감시 채널의 마지막 유입 중 가장 최근. */
  lastTs: string | null;
  ageHours: number | null;
  /** 사용자에게 보여줄 한 줄. state 가 fresh 면 배너를 띄우지 않는다. */
  message: string;
  channels: ChannelFreshness[];
}

const LABEL: Record<ChannelId, string> = {
  sleep: "수면",
  steps: "걸음수",
  active_energy: "활동에너지",
  weight: "체중",
  workout: "운동",
};

/**
 * 전체 상태 판정에 넣는 채널.
 *
 * 하루 등급의 structural·behavioral 구분(DAILY_GRADE_AND_IA_2026-08.md §2.2)을 그대로 쓴다.
 * 워치를 차고 자면 사람이 아무것도 안 해도 매일 생기는 값(수면·걸음수)만 감시한다 —
 * 이 채널이 비면 그건 사용자의 행동이 아니라 **파이프가 죽은 것**이다.
 *
 * 제외:
 *   weight        — 체중계에 올라가야 생긴다. 안 잰 날이 있는 게 정상이다
 *   workout       — 운동을 해야 생긴다. 쉬는 날이 있는 게 정상이다
 *   active_energy — 단축어가 이 값을 내보낼 수 있는지 판정이 "불확실"이다
 *                   (docs/HEALTHKIT_SHORTCUTS_2026-08.md). 항상 채워진다고 가정한
 *                   로직을 만들지 말라는 그 문서의 지시대로 감시에서 뺀다.
 *                   표시는 하되 이것 때문에 경고가 뜨지는 않는다
 */
const MONITORED: ReadonlySet<ChannelId> = new Set<ChannelId>(["sleep", "steps"]);

export function stateFor(ageHours: number | null): FreshnessState {
  if (ageHours == null) return "never";
  if (ageHours >= BROKEN_AFTER_HOURS) return "broken";
  if (ageHours >= STALE_AFTER_HOURS) return "stale";
  return "fresh";
}

function ageHoursOf(lastTs: string | null, now: Date): number | null {
  if (!lastTs) return null;
  const t = new Date(lastTs).getTime();
  if (Number.isNaN(t)) return null;
  // 미래 타임스탬프(기기 시계 어긋남)는 0으로 눕힌다 — 음수 경과시간이 fresh 로
  // 읽히는 것 자체는 맞지만, 화면에 "-3시간 전"이 뜨는 걸 막는다.
  return Math.max(0, (now.getTime() - t) / 3_600_000);
}

/** "3시간 전" · "2일 전" — 배너 문구용. */
export function humanizeAge(ageHours: number | null): string {
  if (ageHours == null) return "기록 없음";
  if (ageHours < 1) return "방금";
  if (ageHours < 24) return `${Math.floor(ageHours)}시간 전`;
  return `${Math.floor(ageHours / 24)}일 전`;
}

/**
 * `subject` 는 문장의 주어다. 감시 채널이 **모두** 같은 상태면 "건강 데이터",
 * 일부만 나쁘면 그 채널 이름("걸음수")이 온다 — 단축어는 항목별로 따로 실패하므로
 * 수면은 멀쩡한데 걸음수만 죽은 날 "건강 데이터가 끊겼어요"라고 하면 틀린 말이 된다.
 */
function messageFor(state: FreshnessState, ageHours: number | null, subject: string): string {
  switch (state) {
    case "fresh":
      return `건강 데이터가 들어오고 있어요 (마지막 ${humanizeAge(ageHours)})`;
    case "stale":
      return `${subject}가 ${humanizeAge(ageHours)}부터 안 들어와요. 아이폰 단축어 자동화를 확인해 주세요.`;
    case "broken":
      return `${subject}가 ${humanizeAge(ageHours)}부터 끊겼어요. 아이폰 단축어 자동화가 꺼졌을 수 있어요.`;
    case "never":
      return `${subject}가 아직 한 번도 들어오지 않았어요. 아이폰 단축어를 설정해 주세요.`;
  }
}

/** state 를 나쁜 순으로 — 감시 채널 중 최악을 고를 때 쓴다. */
const SEVERITY: Record<FreshnessState, number> = { fresh: 0, stale: 1, broken: 2, never: 3 };

export function healthFreshness(lastSeen: ChannelLastSeen[], now: Date = new Date()): HealthFreshness {
  const channels: ChannelFreshness[] = lastSeen.map((c) => {
    const ageHours = ageHoursOf(c.lastTs, now);
    return {
      id: c.id,
      label: LABEL[c.id] ?? c.id,
      lastTs: c.lastTs,
      ageHours,
      state: stateFor(ageHours),
      monitored: MONITORED.has(c.id),
    };
  });

  const monitored = channels.filter((c) => c.monitored);
  if (monitored.length === 0) {
    return {
      state: "never",
      lastTs: null,
      ageHours: null,
      message: messageFor("never", null, "건강 데이터"),
      channels,
    };
  }

  // 최악 채널이 전체 상태다. 수면은 오는데 걸음수가 죽었으면 그건 정상이 아니다 —
  // 단축어는 항목별로 따로 실패할 수 있어서 최신 것 하나로 뭉뚱그리면 놓친다.
  const worst = monitored.reduce((a, b) => (SEVERITY[b.state] > SEVERITY[a.state] ? b : a));
  // 시각·경과는 "가장 최근에 들어온 것" 기준으로 보여준다(가장 오래된 채널 기준으로
  // 쓰면 "41일 전부터 끊겼다"가 실제보다 과장될 수 있다).
  const freshest = monitored.reduce((a, b) => {
    if (a.ageHours == null) return b;
    if (b.ageHours == null) return a;
    return b.ageHours < a.ageHours ? b : a;
  });

  // worst 가 never 면 그 채널엔 시각이 없다 — 화면에 "기록 없음"만 남지 않도록
  // 시각·경과는 살아 있는 채널(freshest) 것을 쓴다.
  const useFreshestTime = worst.state === "never";
  const ageHours = useFreshestTime ? freshest.ageHours : worst.ageHours;
  const allSame = monitored.every((c) => c.state === worst.state);
  return {
    state: worst.state,
    lastTs: useFreshestTime ? freshest.lastTs : worst.lastTs,
    ageHours,
    message: messageFor(worst.state, worst.ageHours, allSame ? "건강 데이터" : worst.label),
    channels,
  };
}
