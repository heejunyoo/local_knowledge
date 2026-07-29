// Swift 원본: LLMAnswerCache.cloudCallBlockReason/recordCloudCall (파일 기반 Usage)를
// settings['llm.cloud_usage']로 이식 — 서버리스에는 상주 프로세스가 없어 파일 저장이
// 무의미하므로, 액션플랜 §P6 작업단계 4가 명시한 "유일하게 허용된 재설계"에 해당한다.
import { getSetting, setSetting } from "@/lib/settings";

/** 원본: minCloudInterval(초) — 클라우드 호출 사이 최소 간격. */
const MIN_INTERVAL_MS = 1200;
/** 원본: softDailyCap */
const SOFT_DAILY_CAP = 400;

interface Usage {
  day: string;
  count: number;
  lastUnix: number;
}

const EMPTY_USAGE: Usage = { day: "", count: 0, lastUnix: 0 };

function dayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

function currentUsage(stored: Usage | null): Usage {
  const day = dayKey();
  if (!stored || stored.day !== day) return { day, count: 0, lastUnix: 0 };
  return stored;
}

export interface LlmThrottleStore {
  /** null이면 호출 허용, 아니면 스킵 사유. */
  blockReason(): Promise<string | null>;
  record(): Promise<void>;
}

export class SettingsLlmThrottleStore implements LlmThrottleStore {
  async blockReason(): Promise<string | null> {
    const stored = await getSetting<Usage>("llm.cloud_usage");
    const usage = currentUsage(stored ?? EMPTY_USAGE);
    const now = Date.now();
    if (now - usage.lastUnix < MIN_INTERVAL_MS) return "cloud-throttle-interval";
    if (usage.count >= SOFT_DAILY_CAP) return "cloud-soft-daily-cap";
    return null;
  }

  async record(): Promise<void> {
    const stored = await getSetting<Usage>("llm.cloud_usage");
    const usage = currentUsage(stored ?? EMPTY_USAGE);
    await setSetting("llm.cloud_usage", {
      day: usage.day,
      count: usage.count + 1,
      lastUnix: Date.now(),
    } satisfies Usage);
  }
}
