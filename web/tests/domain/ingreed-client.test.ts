import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { searchProducts, fetchProductDetail, resetCooldown, FetchFn } from "@/lib/diet/ingreed-client";

const ORIGINAL_ENV = { ...process.env };

function setEnv(): void {
  process.env.INGREED_URL = "https://ingreed.example.supabase.co";
  process.env.INGREED_ANON_KEY = "anon-key-fake";
}

function clearEnv(): void {
  delete process.env.INGREED_URL;
  delete process.env.INGREED_ANON_KEY;
}

const searchItem = {
  report_no: "20030473071214",
  name: "테스트라면",
  maker: "테스트식품",
  category: "면류",
  sub: "유탕면",
  score: 100,
  grade: "A",
  ratable: true,
  mode: "A",
  hidden: false,
};

function okFetch(body: unknown): FetchFn {
  return vi.fn().mockResolvedValue({ ok: true, json: async () => body }) as unknown as FetchFn;
}

function errFetch(status = 500): FetchFn {
  return vi.fn().mockResolvedValue({ ok: false, status, text: async () => "boom" }) as unknown as FetchFn;
}

/** 절대 resolve/reject하지 않는 fetch — withTimeout이 타임아웃으로만 끝나야 한다. */
function hangingFetch(): FetchFn {
  return vi.fn().mockReturnValue(new Promise(() => {})) as unknown as FetchFn;
}

describe("ingreed-client", () => {
  beforeEach(() => {
    resetCooldown();
    setEnv();
  });

  afterEach(() => {
    process.env = { ...ORIGINAL_ENV };
    vi.useRealTimers();
  });

  describe("searchProducts", () => {
    it("정상 응답을 파싱해 돌려준다", async () => {
      const fetchFn = okFetch([searchItem]);
      const result = await searchProducts("테스트라면", 10, fetchFn);
      expect(result).toEqual([searchItem]);
      expect(fetchFn).toHaveBeenCalledTimes(1);
      const [url, init] = (fetchFn as ReturnType<typeof vi.fn>).mock.calls[0];
      expect(url).toBe("https://ingreed.example.supabase.co/rest/v1/rpc/ingreed_search");
      expect(JSON.parse(init.body)).toEqual({ q: "테스트라면", lim: 10, off: 0 });
      expect(init.headers.apikey).toBe("anon-key-fake");
      expect(init.headers.Authorization).toBe("Bearer anon-key-fake");
    });

    it("500 응답이면 null을 반환한다", async () => {
      const fetchFn = errFetch(500);
      const result = await searchProducts("q", 10, fetchFn);
      expect(result).toBeNull();
    });

    it("타임아웃이면 null을 반환한다", async () => {
      vi.useFakeTimers();
      const fetchFn = hangingFetch();
      const promise = searchProducts("q", 10, fetchFn);
      await vi.advanceTimersByTimeAsync(8001);
      const result = await promise;
      expect(result).toBeNull();
    });

    it("환경변수가 없으면 null이고 fetchFn을 부르지 않는다", async () => {
      clearEnv();
      const fetchFn = okFetch([searchItem]);
      const result = await searchProducts("q", 10, fetchFn);
      expect(result).toBeNull();
      expect(fetchFn).not.toHaveBeenCalled();
    });
  });

  describe("fetchProductDetail", () => {
    const detail = { product: { name: "테스트라면", nutrition: { basis: "100g" } }, label: null };

    it("객체로 오는 응답을 그대로 돌려준다", async () => {
      const fetchFn = okFetch(detail);
      const result = await fetchProductDetail("20030473071214", fetchFn);
      expect(result).toEqual(detail);
    });

    it("배열로 감싸 오는 응답도 단일 객체로 normalize한다", async () => {
      const fetchFn = okFetch([detail]);
      const result = await fetchProductDetail("20030473071214", fetchFn);
      expect(result).toEqual(detail);
    });

    it("label이 null이어도 에러 없이 그대로 통과시킨다", async () => {
      const fetchFn = okFetch(detail);
      const result = await fetchProductDetail("20030473071214", fetchFn);
      expect(result?.label).toBeNull();
    });
  });

  describe("쿨다운", () => {
    it("실패 직후 재호출은 쿨다운 동안 fetchFn을 부르지 않는다", async () => {
      const failFetch = errFetch(500);
      const first = await searchProducts("q", 10, failFetch);
      expect(first).toBeNull();
      expect(failFetch).toHaveBeenCalledTimes(1);

      const secondFetch = okFetch([searchItem]);
      const second = await searchProducts("q", 10, secondFetch);
      expect(second).toBeNull();
      expect(secondFetch).not.toHaveBeenCalled();
    });

    it("쿨다운 20초가 지나면 다시 호출한다", async () => {
      vi.useFakeTimers();
      const failFetch = errFetch(500);
      await searchProducts("q", 10, failFetch);

      await vi.advanceTimersByTimeAsync(20001);

      const okAfter = okFetch([searchItem]);
      const result = await searchProducts("q", 10, okAfter);
      expect(result).toEqual([searchItem]);
      expect(okAfter).toHaveBeenCalledTimes(1);
    });

    it("성공하면 쿨다운이 해제되어 바로 다음 호출도 fetchFn을 부른다", async () => {
      // 먼저 실패시켜 쿨다운을 걸고, 테스트가 시간 흐름을 대신해 초기화한다.
      const failFetch = errFetch(500);
      await searchProducts("q", 10, failFetch);
      resetCooldown();

      const okFn = okFetch([searchItem]);
      const successResult = await searchProducts("q", 10, okFn);
      expect(successResult).toEqual([searchItem]);

      // 성공 직후(시간 경과 없이) 다시 실패를 주입 — fetchFn이 불려야 한다(쿨다운이 안 걸려 있었다는 뜻).
      const failAgain = errFetch(500);
      const afterSuccess = await searchProducts("q", 10, failAgain);
      expect(afterSuccess).toBeNull();
      expect(failAgain).toHaveBeenCalledTimes(1);

      // 방금 실패로 새 쿨다운이 걸렸으니 이번엔 바로 다음 호출이 스킵돼야 한다.
      const shouldSkip = okFetch([searchItem]);
      const skipped = await searchProducts("q", 10, shouldSkip);
      expect(skipped).toBeNull();
      expect(shouldSkip).not.toHaveBeenCalled();
    });
  });
});
