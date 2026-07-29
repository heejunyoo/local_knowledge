// Swift 원본: CloudLLMClient.swift 1:1 포트. SDK 미설치 — provider 2종(gemini
// generateContent / openai_compatible chat completions)뿐이라 REST fetch로 충분.
import { ProviderDef, modelsToTry } from "./catalog";

export interface ProviderResult {
  text: string;
  providerId: string;
  model: string;
  engine: string;
}

const SYSTEM_PROMPT =
  "당신은 로컬 개인 비서입니다. 사용자가 준 근거·질문만으로 한국어로 명확히 답하세요.\n" +
  "근거에 없으면 모른다고 말하세요. 추측·장황한 서론 금지. 2~6문장 또는 짧은 불릿.\n" +
  "내부 사고 과정·태그(<think> 등)는 출력하지 마세요.";

/** 원본 CloudLLMClient.clean(_:) 1:1. */
export function clean(raw: string): string {
  let s = raw.trim();

  const openTag = "<think>";
  const closeTag = "</think>";
  const openIdx = s.indexOf(openTag);
  if (openIdx !== -1) {
    const closeIdx = s.indexOf(closeTag, openIdx);
    if (closeIdx !== -1) {
      s = (s.slice(0, openIdx) + s.slice(closeIdx + closeTag.length)).trim();
    } else {
      s = s.slice(openIdx + openTag.length);
      const closeIdx2 = s.indexOf(closeTag);
      if (closeIdx2 !== -1) {
        s = s.slice(closeIdx2 + closeTag.length).trim();
      }
    }
  }

  const marker = "### 답변";
  const markerIdx = s.indexOf(marker);
  if (markerIdx !== -1) {
    s = s.slice(markerIdx + marker.length).trim();
  }

  if (s.length > 2000) {
    s = s.slice(0, 2000) + "…";
  }
  return s;
}

async function withTimeout<T>(timeoutSec: number, fn: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutSec * 1000);
  try {
    return await fn(controller.signal);
  } finally {
    clearTimeout(timer);
  }
}

async function geminiGenerate(
  def: ProviderDef,
  model: string,
  apiKey: string,
  prompt: string,
  maxTokens: number,
  fetchImpl: typeof fetch,
): Promise<string> {
  const base = def.baseUrl.replace(/\/+$/, "");
  const url = `${base}/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const res = await withTimeout(def.timeoutSec, (signal) =>
    fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: maxTokens },
      }),
      signal,
    }),
  );
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`gemini http ${res.status}: ${body.slice(0, 180)}`);
  }
  const obj = (await res.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const parts = obj.candidates?.[0]?.content?.parts ?? [];
  const joined = parts
    .map((p) => p.text ?? "")
    .join("\n")
    .trim();
  if (!joined) throw new Error("gemini empty response");
  return joined;
}

async function openaiChat(
  def: ProviderDef,
  model: string,
  apiKey: string,
  prompt: string,
  maxTokens: number,
  fetchImpl: typeof fetch,
): Promise<string> {
  const base = def.baseUrl.replace(/\/+$/, "");
  const url = `${base}/chat/completions`;
  const res = await withTimeout(def.timeoutSec, (signal) =>
    fetchImpl(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        ...def.extraHeaders,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: prompt },
        ],
        temperature: 0.2,
        max_tokens: maxTokens,
      }),
      signal,
    }),
  );
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`${def.label} http ${res.status}: ${body.slice(0, 180)}`);
  }
  const obj = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const content = (obj.choices?.[0]?.message?.content ?? "").trim();
  if (!content) throw new Error(`${def.label} empty response`);
  return content;
}

/** 원본 CloudLLMClient.complete(providerId:def:apiKey:prompt:maxTokens:) — modelsToTry 순차 시도. */
export async function providerComplete(
  providerId: string,
  def: ProviderDef,
  apiKey: string,
  prompt: string,
  maxTokens: number,
  fetchImpl: typeof fetch = fetch,
): Promise<ProviderResult | null> {
  for (const model of modelsToTry(def)) {
    try {
      const text =
        def.kind === "gemini"
          ? await geminiGenerate(def, model, apiKey, prompt, maxTokens, fetchImpl)
          : await openaiChat(def, model, apiKey, prompt, maxTokens, fetchImpl);
      const cleaned = clean(text);
      if (!cleaned) continue;
      return { text: cleaned, providerId, model, engine: `cloud/${providerId}/${model}` };
    } catch {
      continue;
    }
  }
  return null;
}
