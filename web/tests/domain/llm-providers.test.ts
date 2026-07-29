import { describe, it, expect, vi } from "vitest";
import { clean, providerComplete } from "@/lib/llm/providers";
import { ProviderDef } from "@/lib/llm/catalog";

describe("clean", () => {
  it("앞뒤 공백을 제거한다", () => {
    expect(clean("  hi  ")).toBe("hi");
  });

  it("닫힌 <think> 블록을 제거한다", () => {
    expect(clean("<think>고민중</think>실제 답변")).toBe("실제 답변");
  });

  it("닫히지 않은 <think> 블록은 여는 태그 이후 텍스트를 그대로 남긴다(원본 동작)", () => {
    expect(clean("<think>고민중\n계속 고민")).toBe("고민중\n계속 고민");
  });

  it("### 답변 마커 이후만 남긴다", () => {
    expect(clean("### 근거\n...\n### 답변\n진짜 답")).toBe("진짜 답");
  });

  it("2000자를 넘으면 자르고 … 를 붙인다", () => {
    const long = "가".repeat(2500);
    const result = clean(long);
    expect(result.length).toBe(2001);
    expect(result.endsWith("…")).toBe(true);
  });
});

const geminiDef: ProviderDef = {
  kind: "gemini",
  label: "Gemini",
  baseUrl: "https://gemini.example/v1",
  model: "gemini-main",
  fallbackModels: ["gemini-fallback"],
  apiKeySecret: "gemini_key",
  envFallback: "GEMINI_API_KEY",
  timeoutSec: 5,
  extraHeaders: {},
};

const groqDef: ProviderDef = {
  kind: "openai_compatible",
  label: "Groq",
  baseUrl: "https://groq.example/v1",
  model: "groq-main",
  fallbackModels: [],
  apiKeySecret: "groq_key",
  envFallback: "GROQ_API_KEY",
  timeoutSec: 5,
  extraHeaders: {},
};

describe("providerComplete", () => {
  it("gemini 응답을 파싱해 반환한다", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ candidates: [{ content: { parts: [{ text: "안녕하세요" }] } }] }),
    });
    const result = await providerComplete("gemini", geminiDef, "key", "hi", 100, fetchMock);
    expect(result).toEqual({ text: "안녕하세요", providerId: "gemini", model: "gemini-main", engine: "cloud/gemini/gemini-main" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url] = fetchMock.mock.calls[0];
    expect(url).toContain("gemini-main:generateContent");
  });

  it("openai_compatible 응답을 파싱해 반환한다", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: "hello" } }] }),
    });
    const result = await providerComplete("groq", groqDef, "key", "hi", 100, fetchMock);
    expect(result?.text).toBe("hello");
    expect(result?.engine).toBe("cloud/groq/groq-main");
  });

  it("첫 모델 실패 시 fallback 모델로 넘어간다", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 500, text: async () => "boom" })
      .mockResolvedValueOnce({ ok: true, json: async () => ({ candidates: [{ content: { parts: [{ text: "복구" }] } }] }) });
    const result = await providerComplete("gemini", geminiDef, "key", "hi", 100, fetchMock);
    expect(result?.model).toBe("gemini-fallback");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("모든 모델이 실패하면 null을 반환한다(throw 아님)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: false, status: 500, text: async () => "boom" });
    const result = await providerComplete("gemini", geminiDef, "key", "hi", 100, fetchMock);
    expect(result).toBeNull();
  });
});
