// Swift 원본: LLMProviderCatalog.swift. `config/examples/llm_providers.json`을
// 그대로 정적 import한다(redaction.ts와 동일 근거 — Vercel Root Directory가
// web/이라 런타임 fs 읽기는 배포 시 누락될 수 있고, 정적 import는 빌드 시점에
// 번들에 인라인되어 그 경계와 무관하다). 카탈로그 구조 재설계 금지(액션플랜 §P6-1).
import catalogFile from "../../../config/examples/llm_providers.json";

export interface ProviderDef {
  kind: "gemini" | "openai_compatible";
  label: string;
  baseUrl: string;
  model: string;
  fallbackModels: string[];
  apiKeySecret: string;
  envFallback: string;
  timeoutSec: number;
  extraHeaders: Record<string, string>;
}

export interface LlmCatalog {
  order: string[];
  providers: Record<string, ProviderDef>;
}

interface RawProviderDef {
  kind: string;
  label: string;
  base_url: string;
  model: string;
  fallback_models?: string[];
  api_key_secret: string;
  env_fallback: string;
  timeout_sec: number;
  extra_headers?: Record<string, string>;
}

interface RawCatalogFile {
  order: string[];
  providers: Record<string, RawProviderDef>;
}

function normalize(raw: RawCatalogFile): LlmCatalog {
  const providers: Record<string, ProviderDef> = {};
  for (const [id, p] of Object.entries(raw.providers)) {
    providers[id] = {
      kind: p.kind === "gemini" ? "gemini" : "openai_compatible",
      label: p.label,
      baseUrl: p.base_url,
      model: p.model,
      fallbackModels: p.fallback_models ?? [],
      apiKeySecret: p.api_key_secret,
      envFallback: p.env_fallback,
      timeoutSec: p.timeout_sec,
      extraHeaders: p.extra_headers ?? {},
    };
  }
  return { order: raw.order, providers };
}

let cached: LlmCatalog | null = null;

export function loadCatalog(): LlmCatalog {
  if (!cached) cached = normalize(catalogFile as RawCatalogFile);
  return cached;
}

/** 원본 CloudLLMClient.complete()의 modelsToTry(model + fallbackModels) 순서. */
export function modelsToTry(def: ProviderDef): string[] {
  return [def.model, ...def.fallbackModels];
}
