// 로컬 개발용: 이메일 발송 없이 로그인 링크를 직접 발급한다.
// Supabase 무료 티어의 기본 SMTP는 시간당 발송 건수가 매우 낮아(rate limit)
// 개발 중 로그인 테스트가 자주 막힌다. admin.generateLink()는 메일을 보내지
// 않고 토큰만 만들어 주므로 그 제한과 무관하다.
//
// 실행: npx tsx scripts/generate-magic-link.ts <email> [baseUrl]
//   기본 baseUrl은 http://localhost:3000
//
// 출력된 URL은 1회용이며 만료된다. 문서·커밋에 남기지 말 것.

import path from "node:path";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: path.join(__dirname, "..", ".env.local") });

async function main() {
  const email = process.argv[2];
  const baseUrl = process.argv[3] ?? "http://localhost:3000";
  if (!email) {
    console.error("사용법: npx tsx scripts/generate-magic-link.ts <email> [baseUrl]");
    process.exit(1);
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    console.error("NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY가 .env.local에 없습니다.");
    process.exit(1);
  }

  const supabase = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
  });

  if (error) {
    console.error("링크 생성 실패:", error.message);
    process.exit(1);
  }

  const tokenHash = data.properties.hashed_token;
  console.log("아래 URL을 브라우저에 붙여넣으세요 (1회용):\n");
  console.log(`${baseUrl}/auth/confirm?token_hash=${tokenHash}&type=magiclink`);
}

main();
