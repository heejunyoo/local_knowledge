// npm run test:regression 전용 인증 헬퍼.
//
// lib/rpc/handlers.ts는 lib/supabase/server.ts(next/headers 쿠키 기반)를
// 쓰는데, vitest는 Next 요청 컨텍스트 밖에서 돈다 — next/headers의
// cookies()는 그 밖에서 호출하면 던진다. 그래서 이 회귀 스위트는
// @/lib/supabase/server를 이 파일이 만든 "실 세션이 이미 세팅된
// @supabase/supabase-js 클라이언트"로 vi.mock한다.
//
// 세션은 scripts/generate-magic-link.ts와 같은 방식(admin.generateLink →
// verifyOtp)으로 발급한다 — 메일 발송이 없어 무료 티어 rate limit과 무관하다.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import dotenv from "dotenv";
import path from "node:path";

dotenv.config({ path: path.join(__dirname, "..", "..", ".env.local") });

const OWNER_EMAIL = "naheejun87@gmail.com";

let cached: Promise<SupabaseClient> | null = null;

export function testSupabaseClient(): Promise<SupabaseClient> {
  if (!cached) cached = authenticate();
  return cached;
}

async function authenticate(): Promise<SupabaseClient> {
  const url = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
  const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

  const admin = createClient(url, serviceKey);
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: OWNER_EMAIL,
  });
  if (linkError || !linkData.properties?.hashed_token) {
    throw new Error(`test-client: generateLink failed: ${linkError?.message ?? "no hashed_token"}`);
  }

  const anon = createClient(url, anonKey);
  const { data: verified, error: verifyError } = await anon.auth.verifyOtp({
    type: "magiclink",
    token_hash: linkData.properties.hashed_token,
  });
  if (verifyError || !verified.session) {
    throw new Error(`test-client: verifyOtp failed: ${verifyError?.message ?? "no session"}`);
  }
  return anon;
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`test-client: missing env ${name} (check web/.env.local)`);
  return v;
}
