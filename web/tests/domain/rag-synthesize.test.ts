import { describe, it, expect } from "vitest";
import { synthesize, cleanSnippet, compressSentence, looksLikeDirectAnswer, jaccard } from "@/lib/rag/synthesize";
import type { SynthesizeCitation } from "@/lib/rag/synthesize";

describe("cleanSnippet", () => {
  it("개행/연속 공백을 정규화한다", () => {
    expect(cleanSnippet("가\n\n나   다")).toBe("가 나 다");
  });

  it("마크다운 마커(#, -, *, [..])를 선행 제거한다", () => {
    expect(cleanSnippet("## 제목")).toBe("제목");
    expect(cleanSnippet("- 항목")).toBe("항목");
    expect(cleanSnippet("[태그] 본문")).toBe("본문");
  });
});

describe("compressSentence", () => {
  it("첫 문장부호까지 자른다(20자 이상일 때)", () => {
    const s = "이것은 스무 글자가 넘는 충분히 긴 첫 문장입니다. 그리고 두 번째 문장이 이어집니다.";
    const result = compressSentence(s, 180);
    expect(result.startsWith("이것은 스무 글자가 넘는 충분히 긴 첫 문장입니다.")).toBe(true);
  });

  it("20자 미만 첫 문장이면 자르지 않고 원본 규칙(max 캡)만 적용한다", () => {
    const s = "짧다. 그 다음 내용도 있다.";
    const result = compressSentence(s, 180);
    expect(result).toBe(s);
  });

  it("max를 넘으면 잘라내고 … 을 붙인다", () => {
    const s = "가".repeat(200);
    const result = compressSentence(s, 50);
    expect(result.length).toBe(50);
    expect(result.endsWith("…")).toBe(true);
  });
});

describe("looksLikeDirectAnswer", () => {
  it("질문 토큰의 25% 이상이 텍스트에 있으면 직접 답변으로 간주한다", () => {
    expect(looksLikeDirectAnswer("결제 API 스펙", "결제 API 스펙을 다음 주까지 확정합니다")).toBe(true);
  });

  it("무관한 텍스트는 직접 답변이 아니다", () => {
    expect(looksLikeDirectAnswer("결제 API 스펙", "오늘 날씨가 맑습니다")).toBe(false);
  });
});

describe("jaccard", () => {
  it("동일 문자열은 1을 반환한다", () => {
    expect(jaccard("abc", "abc")).toBe(1);
  });

  it("전혀 겹치지 않으면 0을 반환한다", () => {
    expect(jaccard("abc", "xyz")).toBe(0);
  });
});

describe("synthesize", () => {
  const citation = (over: Partial<SynthesizeCitation>): SynthesizeCitation => ({
    unitId: "u1",
    title: "제목",
    sourceType: "meeting",
    snippet: "내용",
    ...over,
  });

  it("근거/출처 각주를 포함하고 LLM 관련 문구를 노출하지 않는다(원본 RAGTests 정신 반영)", () => {
    const result = synthesize("결제 API 스펙", [
      citation({
        unitId: "meeting:m1",
        title: "스프린트 계획",
        sourceType: "meeting",
        snippet: "다음 주 월요일까지 결제 API 스펙을 확정하기로 했습니다. 담당은 김민수입니다.",
      }),
    ]);
    expect(result).toContain("출처");
    expect(result).not.toContain("LLM 없음");
    expect(result).not.toContain("extractive");
    expect(result).toContain("결제");
  });

  it("최대 5개 citation 중 상위 1개는 리드, 나머지는 최대 3개 support로 구성한다", () => {
    const citations = Array.from({ length: 6 }, (_, i) =>
      citation({
        unitId: `u${i}`,
        title: `문서${i}`,
        snippet: `이것은 문서 ${i}에 관한 서로 다른 독립적인 내용입니다 ${Math.random()}.`,
      }),
    );
    const result = synthesize("문서", citations);
    const supportLines = result.split("\n").filter((l) => l.startsWith("· "));
    expect(supportLines.length).toBeLessThanOrEqual(3);
  });

  it("두 번째·세 번째 citation의 support 라인끼리 유사하면 jaccard로 중복 제거된다", () => {
    // 첫 citation은 lead로 소비되고, 두 번째·세 번째가 support 후보로 서로 비교된다.
    const result = synthesize("무관한 질문 키워드", [
      citation({ unitId: "u1", title: "A", snippet: "리드로 소비되는 완전히 다른 내용의 문장입니다." }),
      citation({ unitId: "u2", title: "B", snippet: "동일한 내용의 지지 문장입니다." }),
      citation({ unitId: "u3", title: "C", snippet: "동일한 내용의 지지 문장입니다." }),
    ]);
    const supportLines = result.split("\n").filter((l) => l.startsWith("· "));
    expect(supportLines.length).toBe(1);
  });

  it("마지막 줄에 distinct unitId 개수를 반영한다", () => {
    const result = synthesize("테스트", [
      citation({ unitId: "u1", snippet: "첫 번째 내용입니다." }),
      citation({ unitId: "u1", snippet: "같은 문서의 다른 청크입니다." }),
      citation({ unitId: "u2", snippet: "두 번째 문서 내용입니다." }),
    ]);
    expect(result).toContain("근거 2개 출처");
  });
});
