import { describe, it, expect } from "vitest";
import {
  healthFreshness,
  stateFor,
  humanizeAge,
  STALE_AFTER_HOURS,
  BROKEN_AFTER_HOURS,
  type ChannelLastSeen,
} from "@/lib/domain/health-freshness";

const NOW = new Date("2026-08-22T12:00:00+09:00");

/** NOW 로부터 h 시간 전 ISO. */
function hoursAgo(h: number): string {
  return new Date(NOW.getTime() - h * 3_600_000).toISOString();
}

function lastSeen(over: Partial<Record<string, string | null>> = {}): ChannelLastSeen[] {
  const base: Record<string, string | null> = {
    sleep: hoursAgo(6),
    steps: hoursAgo(2),
    active_energy: hoursAgo(2),
    weight: hoursAgo(30),
    workout: hoursAgo(50),
  };
  return Object.entries({ ...base, ...over }).map(([id, lastTs]) => ({
    id: id as ChannelLastSeen["id"],
    lastTs,
  }));
}

describe("stateFor", () => {
  it("경계값 — 36h 미만은 fresh, 36h 이상은 stale, 7일 이상은 broken", () => {
    expect(stateFor(STALE_AFTER_HOURS - 0.01)).toBe("fresh");
    expect(stateFor(STALE_AFTER_HOURS)).toBe("stale");
    expect(stateFor(BROKEN_AFTER_HOURS - 0.01)).toBe("stale");
    expect(stateFor(BROKEN_AFTER_HOURS)).toBe("broken");
  });

  it("이력이 없으면 never", () => {
    expect(stateFor(null)).toBe("never");
  });
});

describe("humanizeAge", () => {
  it("1시간 미만은 방금, 하루 미만은 시간, 그 위는 일", () => {
    expect(humanizeAge(0.4)).toBe("방금");
    expect(humanizeAge(5.9)).toBe("5시간 전");
    expect(humanizeAge(49)).toBe("2일 전");
    expect(humanizeAge(null)).toBe("기록 없음");
  });
});

describe("healthFreshness", () => {
  it("감시 채널(수면·걸음수)이 최근이면 fresh — 배너를 띄우지 않는다", () => {
    const r = healthFreshness(lastSeen(), NOW);
    expect(r.state).toBe("fresh");
    expect(r.message).toContain("들어오고 있어요");
  });

  it("체중·운동이 오래돼도 fresh 다 — 사람이 안 한 것이지 파이프가 죽은 게 아니다", () => {
    const r = healthFreshness(lastSeen({ weight: hoursAgo(24 * 40), workout: hoursAgo(24 * 40) }), NOW);
    expect(r.state).toBe("fresh");
  });

  it("활동에너지만 비어도 fresh 다 — 단축어 지원 여부가 불확실한 필드라 감시하지 않는다", () => {
    const r = healthFreshness(lastSeen({ active_energy: null }), NOW);
    expect(r.state).toBe("fresh");
    expect(r.channels.find((c) => c.id === "active_energy")?.monitored).toBe(false);
  });

  it("감시 채널이 하나라도 오래되면 그 채널 이름으로 경고한다", () => {
    const r = healthFreshness(lastSeen({ steps: hoursAgo(40) }), NOW);
    expect(r.state).toBe("stale");
    expect(r.message).toContain("걸음수");
    expect(r.message).not.toContain("건강 데이터가 1일 전부터");
  });

  it("감시 채널이 모두 같은 상태면 주어가 '건강 데이터'다", () => {
    const r = healthFreshness(lastSeen({ sleep: hoursAgo(24 * 41), steps: hoursAgo(24 * 41) }), NOW);
    expect(r.state).toBe("broken");
    expect(r.message).toContain("건강 데이터가 41일 전부터 끊겼어요");
  });

  it("2026-08-22 실제 상태 재현 — 수면은 7/12에 멈췄고 걸음수는 한 건도 없다", () => {
    const r = healthFreshness(
      [
        { id: "sleep", lastTs: "2026-07-12T03:00:00+00:00" },
        { id: "steps", lastTs: null },
        { id: "active_energy", lastTs: null },
        { id: "weight", lastTs: "2026-07-11T23:36:15+00:00" },
        { id: "workout", lastTs: "2026-07-11T10:58:59+00:00" },
      ],
      NOW,
    );
    // 최악 채널은 steps(never). 하지만 시각은 살아 있던 sleep 기준으로 보여준다.
    expect(r.state).toBe("never");
    expect(r.message).toContain("걸음수가 아직 한 번도");
    expect(r.lastTs).toBe("2026-07-12T03:00:00+00:00");
    expect(r.ageHours).not.toBeNull();
  });

  it("전 채널이 비면 never 이고 시각은 없다", () => {
    const r = healthFreshness(
      lastSeen({ sleep: null, steps: null, active_energy: null, weight: null, workout: null }),
      NOW,
    );
    expect(r.state).toBe("never");
    expect(r.lastTs).toBeNull();
    expect(r.ageHours).toBeNull();
  });

  it("기기 시계가 앞서 미래 시각이 와도 음수 경과로 표시하지 않는다", () => {
    const future = new Date(NOW.getTime() + 5 * 3_600_000).toISOString();
    const r = healthFreshness(lastSeen({ sleep: future, steps: future }), NOW);
    expect(r.state).toBe("fresh");
    expect(r.ageHours).toBe(0);
  });
});
