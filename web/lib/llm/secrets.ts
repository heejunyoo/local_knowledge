// Swift 원본: LLMSecrets.resolve(secretKey:envFallback:) — 웹은 secrets.json
// 개념 자체가 없으므로(액션플랜 §P6-2) env_fallback(Vercel 환경변수)만 사용한다.
import { LlmCatalog } from "./catalog";

export function resolveKey(envFallback: string): string | null {
  const v = process.env[envFallback]?.trim();
  return v ? v : null;
}

export function hasAnyCloudKey(catalog: LlmCatalog): boolean {
  return catalog.order.some((id) => {
    const def = catalog.providers[id];
    return def != null && resolveKey(def.envFallback) != null;
  });
}
