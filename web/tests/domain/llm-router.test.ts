import { describe, it, expect, vi, afterEach } from "vitest";
import { complete } from "@/lib/llm/router";
import { CachedAnswer, LlmAnswerCacheStore } from "@/lib/llm/cache";
import { LlmThrottleStore } from "@/lib/llm/throttle";

class FakeCacheStore implements LlmAnswerCacheStore {
  private map = new Map<string, CachedAnswer>();
  async get(key: string): Promise<CachedAnswer | null> {
    const hit = this.map.get(key);
    return hit ? { text: hit.text, engine: `${hit.engine}+cache` } : null;
  }
  async put(key: string, _question: string, answer: CachedAnswer): Promise<void> {
    this.map.set(key, answer);
  }
}

class FakeThrottleStore implements LlmThrottleStore {
  blocked: string | null = null;
  recorded = 0;
  async blockReason(): Promise<string | null> {
    return this.blocked;
  }
  async record(): Promise<void> {
    this.recorded++;
  }
}

const ENV_KEYS = ["GROQ_API_KEY", "GEMINI_API_KEY", "OPENROUTER_API_KEY"] as const;
const originalEnv: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) originalEnv[k] = process.env[k];

afterEach(() => {
  for (const k of ENV_KEYS) {
    if (originalEnv[k] === undefined) delete process.env[k];
    else process.env[k] = originalEnv[k];
  }
});

function geminiOk(text: string) {
  return { ok: true, json: async () => ({ candidates: [{ content: { parts: [{ text }] } }] }) };
}
function httpFail(status = 500) {
  return { ok: false, status, text: async () => "fail" };
}

describe("llm/router.complete — G6-2 캐스케이드 전이", () => {
  it("첫 provider(groq) 키가 없으면 다음 provider(gemini)로 전이한다", async () => {
    delete process.env.GROQ_API_KEY;
    process.env.GEMINI_API_KEY = "gemini-key";
    delete process.env.OPENROUTER_API_KEY;

    const fetchMock = vi.fn().mockImplementation((url: string) => {
      expect(url).toContain("generativelanguage.googleapis.com");
      return Promise.resolve(geminiOk("gemini 답변"));
    });

    const result = await complete({
      prompt: "테스트 질문",
      cacheStore: new FakeCacheStore(),
      throttleStore: new FakeThrottleStore(),
      fetchImpl: fetchMock,
    });

    expect(result?.text).toBe("gemini 답변");
    expect(result?.engine).toBe("cloud/gemini/gemini-2.5-flash");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("groq 요청이 실패하면 gemini로 전이한다", async () => {
    process.env.GROQ_API_KEY = "groq-key";
    process.env.GEMINI_API_KEY = "gemini-key";
    delete process.env.OPENROUTER_API_KEY;

    const fetchMock = vi.fn().mockImplementation((url: string) => {
      if (url.includes("groq.com")) return Promise.resolve(httpFail());
      return Promise.resolve(geminiOk("gemini 복구"));
    });

    const result = await complete({
      prompt: "테스트 질문 2",
      cacheStore: new FakeCacheStore(),
      throttleStore: new FakeThrottleStore(),
      fetchImpl: fetchMock,
    });

    expect(result?.text).toBe("gemini 복구");
    expect(result?.engine).toContain("cloud/gemini/");
  });
});

describe("llm/router.complete — G6-3★ 전면 실패 시 null(에러 아님)", () => {
  it("모든 provider가 실패하면 throw 없이 null을 반환한다", async () => {
    process.env.GROQ_API_KEY = "groq-key";
    process.env.GEMINI_API_KEY = "gemini-key";
    process.env.OPENROUTER_API_KEY = "openrouter-key";
    const fetchMock = vi.fn().mockResolvedValue(httpFail(503));

    const result = await complete({
      prompt: "실패 시나리오",
      cacheStore: new FakeCacheStore(),
      throttleStore: new FakeThrottleStore(),
      fetchImpl: fetchMock,
    });

    expect(result).toBeNull();
  });

  it("클라우드 키가 하나도 없으면 fetch 없이 즉시 null을 반환한다", async () => {
    delete process.env.GROQ_API_KEY;
    delete process.env.GEMINI_API_KEY;
    delete process.env.OPENROUTER_API_KEY;
    const fetchMock = vi.fn();

    const result = await complete({
      prompt: "키 없음",
      cacheStore: new FakeCacheStore(),
      throttleStore: new FakeThrottleStore(),
      fetchImpl: fetchMock,
    });

    expect(result).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("llm/router.complete — G6-4 캐시", () => {
  it("동일 prompt를 2회 호출하면 provider fetch는 1회만 일어난다", async () => {
    process.env.GROQ_API_KEY = "groq-key";
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve({ ok: true, json: async () => ({ choices: [{ message: { content: "캐시될 답변" } }] }) }),
    );
    const cacheStore = new FakeCacheStore();
    const throttleStore = new FakeThrottleStore();

    const first = await complete({ prompt: "캐시 테스트", cacheStore, throttleStore, fetchImpl: fetchMock });
    const second = await complete({ prompt: "캐시 테스트", cacheStore, throttleStore, fetchImpl: fetchMock });

    expect(first?.text).toBe("캐시될 답변");
    expect(second?.text).toBe("캐시될 답변");
    expect(second?.engine).toContain("+cache");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(throttleStore.recorded).toBe(1);
  });
});

describe("llm/router.complete — G6-5 redaction", () => {
  it("민감 패턴이 포함된 prompt는 클라우드 호출 자체를 하지 않는다", async () => {
    process.env.GROQ_API_KEY = "groq-key";
    const fetchMock = vi.fn();

    const result = await complete({
      prompt: "내 AWS 키는 AKIAABCDEFGHIJKLMNOP 입니다",
      cacheStore: new FakeCacheStore(),
      throttleStore: new FakeThrottleStore(),
      fetchImpl: fetchMock,
    });

    expect(result).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("llm/router.complete — throttle", () => {
  it("throttle이 차단하면 클라우드 호출 없이 null을 반환한다", async () => {
    process.env.GROQ_API_KEY = "groq-key";
    const fetchMock = vi.fn();
    const throttleStore = new FakeThrottleStore();
    throttleStore.blocked = "cloud-soft-daily-cap";

    const result = await complete({
      prompt: "throttle 테스트",
      cacheStore: new FakeCacheStore(),
      throttleStore,
      fetchImpl: fetchMock,
    });

    expect(result).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
