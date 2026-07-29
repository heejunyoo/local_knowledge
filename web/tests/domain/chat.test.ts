import { describe, it, expect } from "vitest";
import { classifyIntent, firstInt, firstDouble } from "@/lib/domain/chat";

describe("classifyIntent", () => {
  it("mode가 명시되면 그대로 사용한다", () => {
    expect(classifyIntent("아무 말", "diet")).toBe("diet");
    expect(classifyIntent("아무 말", "knowledge")).toBe("knowledge");
    expect(classifyIntent("아무 말", "mixed")).toBe("mixed");
  });

  it("식단 관련 단서가 있으면 diet로 분류한다", () => {
    expect(classifyIntent("점심에 뭘 먹었더라", "auto")).toBe("diet");
    expect(classifyIntent("운동 30분 했어요", "auto")).toBe("diet");
  });

  it("지식 관련 단서가 있으면 knowledge로 분류한다", () => {
    expect(classifyIntent("지난주 회의 요약해줘", "auto")).toBe("knowledge");
  });

  it("단서가 없으면 기본값은 knowledge다", () => {
    expect(classifyIntent("안녕하세요", "auto")).toBe("knowledge");
  });

  it("diet+knowledge 단서가 동시에 있으면 mixed로 분류한다", () => {
    expect(classifyIntent("이번 주 회의랑 식사 같이 정리해줘", "auto")).toBe("mixed");
  });

  it("단백질+회의/목표 조합은 mixed로 분류한다(원본 명시 템플릿)", () => {
    expect(classifyIntent("단백질 목표 얼마였지", "auto")).toBe("mixed");
  });
});

describe("firstInt", () => {
  it("문자열 내 첫 정수를 반환한다", () => {
    expect(firstInt("운동 30분 했어요")).toBe(30);
  });
  it("정수가 없으면 null", () => {
    expect(firstInt("운동 했어요")).toBeNull();
  });
});

describe("firstDouble", () => {
  it("소수를 포함한 첫 숫자를 반환한다", () => {
    expect(firstDouble("450.5 kcal 먹었어요")).toBe(450.5);
  });
  it("정수만 있어도 반환한다", () => {
    expect(firstDouble("500 kcal")).toBe(500);
  });
});
