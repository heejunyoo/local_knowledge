// Swift 원본: KnowledgeRAG.swift의 ask()/refine()/askFast() 1:1 포트.
import { complete as routerComplete } from "@/lib/llm/router";
import { DbLlmAnswerCacheStore } from "@/lib/llm/db-cache-store";
import { SettingsLlmThrottleStore } from "@/lib/llm/throttle";
import { ragPrompt } from "./prompt";
import { synthesize } from "./synthesize";
import { Citation, fetchCitations } from "./citations";

export interface RagAnswer {
  question: string;
  answer: string;
  citations: Citation[];
  engine: string;
}

const EMPTY_QUESTION_ANSWER = "질문을 입력해 주세요.";
const NOT_FOUND_ANSWER =
  "모은 지식에서 관련 내용을 찾지 못했어요.\n\n· 미팅을 저장했는지\n· 지식 연결에서 동기화했는지\n를 확인해 주세요.";

/** 원본 isPlausibleAnswer(_:). */
function isPlausibleAnswer(s: string): boolean {
  const t = s.trim();
  if (t.length < 12 || t.length > 1600) return false;
  if (t.includes("### 근거") || t.includes("### 질문")) return false;
  if (t.toLowerCase().includes("as an ai")) return false;
  if (t.includes("<think>") || t.includes("</think>")) return false;
  return true;
}

/** 원본 appendCitationFooterIfNeeded(answer:citations:) — W0 G-Trust: 근거 제목을 항상 노출. */
function appendCitationFooterIfNeeded(answer: string, citations: Citation[]): string {
  const titles = citations
    .slice(0, 3)
    .map((c) => c.title)
    .filter((t) => t.length > 0);
  if (titles.length === 0) return answer;
  const lower = answer.toLowerCase();
  if (answer.includes("근거") || answer.includes("출처") || lower.includes("source")) return answer;
  const line = "근거: " + titles.map((t) => `「${t}」`).join(", ");
  return `${answer}\n\n${line}`;
}

/** 원본 refine(question:citations:knowledgeRoot:useLlama:). citations가 비어있으면 null. */
export async function refine(question: string, citations: Citation[]): Promise<RagAnswer | null> {
  if (citations.length === 0) return null;
  const ctx = citations.slice(0, 3).map((c) => ({
    title: c.title,
    snippet: c.snippet.length > 220 ? c.snippet.slice(0, 220) + "…" : c.snippet,
  }));
  const prompt = ragPrompt(question, ctx);
  const gen = await routerComplete({
    prompt,
    maxTokens: 420,
    cacheStore: new DbLlmAnswerCacheStore(),
    throttleStore: new SettingsLlmThrottleStore(),
  });
  if (!gen || !isPlausibleAnswer(gen.text)) return null;
  const text = appendCitationFooterIfNeeded(gen.text.trim(), citations);
  return { question, answer: text, citations, engine: `${gen.engine}+retrieve-v2` };
}

export interface AskOptions {
  topK?: number;
  useLlm?: boolean;
}

/** 원본 ask(question:store:knowledgeRoot:topK:useLlama:). */
export async function ask(question: string, opts: AskOptions = {}): Promise<RagAnswer> {
  const q = question.trim();
  if (!q) {
    return { question, answer: EMPTY_QUESTION_ANSWER, citations: [], engine: "extractive-rag/v1" };
  }

  const citations = await fetchCitations(q, { limit: opts.topK ?? 8 });
  if (citations.length === 0) {
    return { question: q, answer: NOT_FOUND_ANSWER, citations: [], engine: "retrieve-v2" };
  }

  if (opts.useLlm ?? true) {
    const refined = await refine(q, citations);
    if (refined) return refined;
  }

  return { question: q, answer: synthesize(q, citations), citations, engine: "extractive-rag/v2" };
}

/** 원본 askFast(question:store:topK:) — 검색+extractive만(LLM 스킵, UI 즉시 응답용). */
export async function askFast(question: string, opts: { topK?: number } = {}): Promise<RagAnswer> {
  return ask(question, { topK: opts.topK, useLlm: false });
}
