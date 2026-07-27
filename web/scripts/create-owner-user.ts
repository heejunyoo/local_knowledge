// P3-1: 신규 가입을 막은 뒤(Dashboard에서 수동 처리) 오너 계정 1개만
// service_role 키로 직접 생성한다. 1회성 스크립트 — 반복 실행해도 같은 이메일이면
// Supabase가 중복 가입 에러를 반환하므로 안전하다.
//
// 실행: npx tsx scripts/create-owner-user.ts <email>
// 출력된 user id를 docs/ENV_VARS.md의 owner_id backfill 절차에 사용한다.

import path from "node:path";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: path.join(__dirname, "..", ".env.local") });

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error("사용법: npx tsx scripts/create-owner-user.ts <email>");
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

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    email_confirm: true,
  });

  if (error) {
    console.error("계정 생성 실패:", error.message);
    process.exit(1);
  }

  console.log("생성됨. user id:", data.user.id);
  console.log("이 id로 docs/ENV_VARS.md의 owner_id backfill UPDATE 14건을 실행하세요.");
}

main();
