import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { isCronAuthorized } from "@/lib/cron";

describe("isCronAuthorized", () => {
  const original = process.env.CRON_SECRET;

  afterEach(() => {
    process.env.CRON_SECRET = original;
  });

  it("CRON_SECRET과 일치하는 Bearer 헤더는 통과된다", () => {
    process.env.CRON_SECRET = "test-secret";
    expect(isCronAuthorized("Bearer test-secret")).toBe(true);
  });

  it("불일치 헤더는 거부된다", () => {
    process.env.CRON_SECRET = "test-secret";
    expect(isCronAuthorized("Bearer wrong")).toBe(false);
  });

  it("헤더 없음은 거부된다", () => {
    process.env.CRON_SECRET = "test-secret";
    expect(isCronAuthorized(null)).toBe(false);
  });

  it("CRON_SECRET 미설정이면 어떤 헤더도 통과하지 못한다 (기본값 차단)", () => {
    delete process.env.CRON_SECRET;
    expect(isCronAuthorized("Bearer undefined")).toBe(false);
    expect(isCronAuthorized(null)).toBe(false);
  });
});
