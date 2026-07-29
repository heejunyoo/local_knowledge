// G4b-4: 단식 리마인더 이메일 발화 인프라 — markFastingReminderSent 실제 DB 왕복.
// 실제 Supabase 프로젝트 대상(web/.env.local 필요).
import { describe, it, expect, vi } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { startFast, endFast, markFastingReminderSent, fetchFastingPrefs } = await import("@/lib/db/diet");

describe("G4b-4: markFastingReminderSent 실제 DB 왕복", () => {
  it("활성 세션에 reminderSentAt을 기록하고, 종료 후 원복된다", async () => {
    const before = await fetchFastingPrefs();
    if (before.active && before.active.endedAt == null) {
      // 오너의 실제 활성 세션이 있으면 건드리지 않고 스킵.
      return;
    }

    const session = await startFast(14);
    try {
      expect(session.reminderSentAt).toBeNull();
      const at = new Date();
      await markFastingReminderSent(session.id, at);
      const after = await fetchFastingPrefs();
      expect(after.active?.reminderSentAt).toBe(at.toISOString());
    } finally {
      await endFast("test-cleanup");
    }

    const restored = await fetchFastingPrefs();
    expect(restored.active).toBeNull();
  });

  it("세션 id가 일치하지 않으면 조용히 스킵한다(경합 안전장치)", async () => {
    const before = await fetchFastingPrefs();
    if (before.active && before.active.endedAt == null) return;

    const session = await startFast(14);
    try {
      await markFastingReminderSent("nonexistent-id", new Date());
      const after = await fetchFastingPrefs();
      expect(after.active?.reminderSentAt).toBeNull();
      expect(after.active?.id).toBe(session.id);
    } finally {
      await endFast("test-cleanup");
    }
  });
});
