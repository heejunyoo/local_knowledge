import { describe, it, expect, afterEach } from "vitest";
import { isIngestAuthorized } from "@/lib/ingest-auth";

describe("isIngestAuthorized", () => {
  const original = process.env.INGEST_API_TOKEN;

  afterEach(() => {
    process.env.INGEST_API_TOKEN = original;
  });

  it("INGEST_API_TOKEN과 일치하는 Bearer 헤더는 통과된다", () => {
    process.env.INGEST_API_TOKEN = "test-token";
    expect(isIngestAuthorized("Bearer test-token")).toBe(true);
  });

  it("불일치 헤더는 거부된다", () => {
    process.env.INGEST_API_TOKEN = "test-token";
    expect(isIngestAuthorized("Bearer wrong")).toBe(false);
  });

  it("헤더 없음은 거부된다", () => {
    process.env.INGEST_API_TOKEN = "test-token";
    expect(isIngestAuthorized(null)).toBe(false);
  });

  it("INGEST_API_TOKEN 미설정이면 어떤 헤더도 통과하지 못한다 (기본값 차단)", () => {
    delete process.env.INGEST_API_TOKEN;
    expect(isIngestAuthorized("Bearer undefined")).toBe(false);
    expect(isIngestAuthorized(null)).toBe(false);
  });
});
