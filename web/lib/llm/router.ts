// Swift 원본: LLMRouter.swift. 캐스케이드: 캐시 → 클라우드(키 있는 provider만,
// order 순서, redaction+throttle 통과 시) → 로컬 7B(서버리스 이식 불가, 스킵) → null.
import { scan } from "@/lib/redaction";
import { loadCatalog } from "./catalog";
import { hasAnyCloudKey, resolveKey } from "./secrets";
import { providerComplete } from "./providers";
import { cacheKey, LlmAnswerCacheStore } from "./cache";
import { LlmThrottleStore } from "./throttle";

export interface CompleteOptions {
  prompt: string;
  maxTokens?: number;
  cacheStore: LlmAnswerCacheStore;
  throttleStore: LlmThrottleStore;
  fetchImpl?: typeof fetch;
}

export interface CompleteAnswer {
  text: string;
  engine: string;
}

export async function complete(opts: CompleteOptions): Promise<CompleteAnswer | null> {
  const maxTokens = opts.maxTokens ?? 512;
  const fetchImpl = opts.fetchImpl ?? fetch;
  const catalog = loadCatalog();

  // 0) 캐시 — 동일 prompt는 free-tier RPD/TPM을 다시 태우지 않는다.
  const key = cacheKey(opts.prompt, maxTokens);
  const hit = await opts.cacheStore.get(key);
  if (hit) return hit;

  // 1) 클라우드 — 키가 있는 provider만, catalog.order 순서 유지.
  if (hasAnyCloudKey(catalog)) {
    const redaction = scan(opts.prompt);
    if (redaction.allowed) {
      const block = await opts.throttleStore.blockReason();
      if (!block) {
        const cloud = await tryCloud(opts.prompt, maxTokens, fetchImpl);
        if (cloud) {
          await opts.throttleStore.record();
          await opts.cacheStore.put(key, opts.prompt, cloud, cloud.engine);
          return cloud;
        }
      }
    }
  }

  // 2) 로컬 7B — Vercel(서버리스)에는 상주 프로세스/로컬 바이너리가 없어
  // 원본의 LocalLLM 단계를 이식할 수 없다(방향성 §6.5.3, 상주 워커 금지).
  // 클라우드가 없거나 전부 실패하면 바로 (3) extractive로 떨어진다 —
  // 호출부(web/lib/rag/ask.ts)가 null을 받으면 synthesize()를 호출하는 것으로
  // 이 단계를 대체한다. G6-3이 이 대체가 "에러가 아니라 정상 1급 경로"임을
  // 강제한다.

  return null;
}

async function tryCloud(
  prompt: string,
  maxTokens: number,
  fetchImpl: typeof fetch,
): Promise<CompleteAnswer | null> {
  const catalog = loadCatalog();
  const keyed = catalog.order.filter((id) => {
    const def = catalog.providers[id];
    return def != null && resolveKey(def.envFallback) != null;
  });
  for (const id of keyed) {
    const def = catalog.providers[id];
    const key = resolveKey(def.envFallback);
    if (!key) continue;
    const result = await providerComplete(id, def, key, prompt, maxTokens, fetchImpl);
    if (result) return { text: result.text, engine: result.engine };
  }
  return null;
}
