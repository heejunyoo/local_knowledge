// Swift 원본: Packages/KnowledgeWorkers/Sources/KnowledgeWorkers/LLMAnswerCache.swift
import { createHash } from "node:crypto";

/** 원본: ttlSeconds — 동일 prompt는 이 기간 내 재호출하지 않는다(free-tier RPD 절약). */
export const TTL_SECONDS = 7 * 24 * 3600;
/** 원본: maxEntries */
export const MAX_ENTRIES = 300;

/** 원본: cacheKey(prompt:maxTokens:) 1:1 — sha256("v1|maxTokens|정규화prompt"). */
export function cacheKey(prompt: string, maxTokens: number): string {
  const norm = prompt.trim().replace(/\s+/g, " ");
  const material = `v1|${maxTokens}|${norm}`;
  return createHash("sha256").update(material, "utf8").digest("hex");
}

export interface CachedAnswer {
  text: string;
  engine: string;
}

export interface LlmAnswerCacheStore {
  /** hit 시 answer.engine에 "+cache" 접미사를 붙여 반환해야 한다(원본 LLMAnswerCache.get() 계약). */
  get(key: string): Promise<CachedAnswer | null>;
  /** provider는 "+cache" 접미사가 제거된 원본 엔진 식별자. */
  put(key: string, question: string, answer: CachedAnswer, provider: string): Promise<void>;
}
