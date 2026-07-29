import { describe, it, expect, afterEach, vi } from "vitest";
import { sendFastingReminderEmail } from "@/lib/email/resend";

describe("sendFastingReminderEmail", () => {
  const original = process.env.RESEND_API_KEY;

  afterEach(() => {
    process.env.RESEND_API_KEY = original;
  });

  it("RESEND_API_KEY 미설정이면 발송을 스킵한다(에러 아님)", async () => {
    delete process.env.RESEND_API_KEY;
    const fetchMock = vi.fn();
    const result = await sendFastingReminderEmail(
      { to: "a@example.com", targetHours: 14, elapsedHours: 14.5 },
      fetchMock,
    );
    expect(result).toEqual({ sent: false, skippedReason: "RESEND_API_KEY not configured" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("키가 있으면 Resend API를 호출하고 to/제목에 목표 시간을 반영한다", async () => {
    process.env.RESEND_API_KEY = "test-key";
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, text: async () => "" });
    const result = await sendFastingReminderEmail(
      { to: "a@example.com", targetHours: 14, elapsedHours: 14.5 },
      fetchMock,
    );
    expect(result).toEqual({ sent: true });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.resend.com/emails");
    expect(opts.headers.Authorization).toBe("Bearer test-key");
    const body = JSON.parse(opts.body);
    expect(body.to).toEqual(["a@example.com"]);
    expect(body.subject).toContain("14시간");
  });

  it("Resend API가 실패 응답을 반환하면 throw한다", async () => {
    process.env.RESEND_API_KEY = "test-key";
    const fetchMock = vi.fn().mockResolvedValue({ ok: false, status: 422, text: async () => "bad request" });
    await expect(
      sendFastingReminderEmail({ to: "a@example.com", targetHours: 14, elapsedHours: 14.5 }, fetchMock),
    ).rejects.toThrow(/422/);
  });
});
