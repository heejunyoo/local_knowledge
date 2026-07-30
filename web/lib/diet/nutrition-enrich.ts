// C3: diet.estimate_nutrition의 LLM 보강 오케스트레이터.
// lib/rag/ask.ts가 라우터에 스토어를 주입하는 것과 같은 배선이고,
// 판단 로직은 전부 lib/domain/diet-nutrition-llm.ts(순수)에 있다.
import { Estimate, EstimateSource } from "@/lib/domain/diet-nutrition-calc";
import { applyPer100, nutritionPrompt, parsePer100 } from "@/lib/domain/diet-nutrition-llm";
import { complete as routerComplete, CompleteAnswer } from "@/lib/llm/router";
import { DbLlmAnswerCacheStore } from "@/lib/llm/db-cache-store";
import { SettingsLlmThrottleStore } from "@/lib/llm/throttle";

/** 100단위 숫자 두 개만 받으면 되므로 짧게 끊는다(빠른입력은 사용자 대기 경로). */
const MAX_TOKENS = 80;

export type CompleteFn = (prompt: string, maxTokens: number) => Promise<CompleteAnswer | null>;

export interface EnrichedEstimate {
  estimate: Estimate;
  source: EstimateSource;
}

async function defaultComplete(prompt: string, maxTokens: number): Promise<CompleteAnswer | null> {
  return routerComplete({
    prompt,
    maxTokens,
    cacheStore: new DbLlmAnswerCacheStore(),
    throttleStore: new SettingsLlmThrottleStore(),
  });
}

/**
 * 카탈로그가 맞춘 추정치는 그대로 통과시키고(LLM 호출 0회), 못 맞춘 것만 LLM에 묻는다.
 *
 * 키 없음·스로틀 차단·파싱 실패·범위 밖 값·라우터 예외는 전부 **에러가 아니라**
 * 기존 일반식 평균 추정치로의 폴백이다 — G6-3(전면 실패 시 extractive)과 같은 원칙.
 */
export async function enrichWithLlm(
  estimate: Estimate,
  completeFn: CompleteFn = defaultComplete,
): Promise<EnrichedEstimate> {
  if (estimate.matchedCatalog) return { estimate, source: "catalog" };

  let gen: CompleteAnswer | null = null;
  try {
    gen = await completeFn(nutritionPrompt(estimate.foodName, estimate.unit), MAX_TOKENS);
  } catch {
    return { estimate, source: "generic" };
  }
  if (!gen) return { estimate, source: "generic" };

  const per100 = parsePer100(gen.text);
  if (!per100) return { estimate, source: "generic" };

  return { estimate: applyPer100(estimate, per100), source: "llm" };
}
