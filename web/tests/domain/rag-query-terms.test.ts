import { describe, it, expect } from "vitest";
import { tokens, expand } from "@/lib/rag/query-terms";

describe("tokens", () => {
  it("공백/구두점으로 분리하고 길이 2 미만은 버린다", () => {
    expect(tokens("hello, world! a")).toEqual(["hello", "world"]);
  });
});

describe("expand", () => {
  it("한글 질의에서 bigram/trigram을 추가한다", () => {
    const terms = expand("결제 API");
    expect(terms).toContain("결제");
    expect(terms).toContain("API");
  });

  it("불용어(1글자 조사 등)를 제거한다", () => {
    const terms = expand("이것은 무엇인가요");
    expect(terms).not.toContain("은");
    expect(terms).not.toContain("무엇");
  });

  it("결과는 중복 없이 정렬되어 반환된다", () => {
    const terms = expand("결제 결제");
    const unique = Array.from(new Set(terms));
    expect(terms).toEqual(unique);
    expect(terms).toEqual([...terms].sort());
  });
});
