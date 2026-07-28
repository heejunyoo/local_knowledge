import { describe, it, expect } from "vitest";
import { parseIngestNumber, parseIngestTs, resolveIntensity } from "@/lib/health-ingest";

describe("parseIngestNumber", () => {
  it("숫자는 그대로, 숫자 문자열은 변환, 그 외는 null", () => {
    expect(parseIngestNumber(3.5)).toBe(3.5);
    expect(parseIngestNumber("3.5")).toBe(3.5);
    expect(parseIngestNumber("")).toBeNull();
    expect(parseIngestNumber("abc")).toBeNull();
    expect(parseIngestNumber(undefined)).toBeNull();
    expect(parseIngestNumber(null)).toBeNull();
  });
});

describe("parseIngestTs", () => {
  it("유효한 ISO 문자열은 파싱하고, 없거나 무효하면 현재 시각으로 대체한다", () => {
    const d = parseIngestTs("2026-07-27T10:00:00Z");
    expect(d.toISOString()).toBe("2026-07-27T10:00:00.000Z");

    const before = Date.now();
    const fallback = parseIngestTs("not-a-date");
    expect(fallback.getTime()).toBeGreaterThanOrEqual(before);

    const fallback2 = parseIngestTs(undefined);
    expect(fallback2.getTime()).toBeGreaterThanOrEqual(before);
  });
});

describe("resolveIntensity", () => {
  it("healthkit이면 그대로, 아니면 source 문자열을 그대로 쓴다", () => {
    expect(resolveIntensity("healthkit")).toBe("healthkit");
    expect(resolveIntensity("garmin")).toBe("garmin");
  });
});
