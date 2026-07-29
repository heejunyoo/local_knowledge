import { describe, it, expect } from "vitest";
import { cacheKey } from "@/lib/llm/cache";

describe("cacheKey", () => {
  it("동일 prompt+maxTokens는 동일 키를 낸다", () => {
    expect(cacheKey("hello world", 512)).toBe(cacheKey("hello world", 512));
  });

  it("공백 정규화 후 동일하면 같은 키를 낸다(trim + 연속 공백 축약)", () => {
    expect(cacheKey("  hello   world  ", 512)).toBe(cacheKey("hello world", 512));
  });

  it("maxTokens가 다르면 다른 키를 낸다", () => {
    expect(cacheKey("hello world", 512)).not.toBe(cacheKey("hello world", 256));
  });

  it("prompt가 다르면 다른 키를 낸다", () => {
    expect(cacheKey("hello", 512)).not.toBe(cacheKey("world", 512));
  });

  it("64자리 hex(sha256)를 반환한다", () => {
    expect(cacheKey("x", 1)).toMatch(/^[0-9a-f]{64}$/);
  });
});
