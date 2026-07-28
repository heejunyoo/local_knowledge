// P-1 패턴 (방향성 §6.5.4, 액션플랜 §P4a 작업 단계 1):
// DB `settings` 키-값 테이블을 모듈 스코프 캐시로 감싼다. KnowledgeApp의
// config/features.json·app.json 같은 로컬 파일 설정을 Vercel(파일 없음)에서
// 대체하는 자리다.
import { createClient } from "@/lib/supabase/server";

const DEFAULT_TTL_MS = 60_000;

interface CacheEntry {
  value: unknown;
  expiresAt: number;
}

// 이 Map은 하나의 서버리스 함수 웜 인스턴스 생애주기 동안만 유효하다 —
// 인스턴스·리전 간에 공유되지 않는다. 다른 인스턴스가 쓴 최신값은 최대
// DEFAULT_TTL_MS(또는 opts.ttlMs)만큼 지연되어 보이며, 직접 쓴 값을 바로
// 읽어야 하는 호출부는 opts.refresh(예: 라우트의 `?refresh=1`)로 우회한다.
const cache = new Map<string, CacheEntry>();

async function currentOwnerId(
  supabase: Awaited<ReturnType<typeof createClient>>,
): Promise<string> {
  const { data } = await supabase.auth.getClaims();
  const ownerId = data?.claims.sub;
  if (!ownerId) throw new Error("settings: no authenticated user");
  return ownerId;
}

export async function getSetting<T = unknown>(
  key: string,
  opts: { refresh?: boolean; ttlMs?: number } = {},
): Promise<T | null> {
  const supabase = await createClient();
  const ownerId = await currentOwnerId(supabase);
  const cacheKey = `${ownerId}:${key}`;
  const now = Date.now();

  if (!opts.refresh) {
    const cached = cache.get(cacheKey);
    if (cached && cached.expiresAt > now) return cached.value as T;
  }

  const { data, error } = await supabase
    .from("settings")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  if (error) throw error;

  const value = (data?.value ?? null) as T | null;
  cache.set(cacheKey, { value, expiresAt: now + (opts.ttlMs ?? DEFAULT_TTL_MS) });
  return value;
}

export async function setSetting(key: string, value: unknown): Promise<void> {
  const supabase = await createClient();
  const ownerId = await currentOwnerId(supabase);

  const { error } = await supabase
    .from("settings")
    .upsert({ owner_id: ownerId, key, value, updated_at: new Date().toISOString() });
  if (error) throw error;

  cache.set(`${ownerId}:${key}`, { value, expiresAt: Date.now() + DEFAULT_TTL_MS });
}
