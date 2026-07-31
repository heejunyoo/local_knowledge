// 오너 계정의 비밀번호를 로컬에서 직접 정한다(이메일 왕복 없음).
//
// 매직링크는 최초 로그인마다 메일함을 왕복해야 하고 무료 티어 SMTP rate limit에도
// 걸린다. 비밀번호를 한 번 정해두면 브라우저가 자격증명을 저장해 사실상 1탭으로
// 끝난다. 이 스크립트는 그 "한 번"을 브라우저 없이 해치우는 용도다.
//
// 실행: npx tsx web/scripts/set-password.ts [email]
//   비밀번호는 화면에 찍히지 않고, 어디에도 저장되지 않는다.
//
// 로그인한 뒤 앱 안에서 바꾸려면 설정 → 계정 → 비밀번호 저장을 쓰면 된다.

import path from "node:path";
import readline from "node:readline";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: path.join(__dirname, "..", ".env.local") });

const DEFAULT_EMAIL = "naheejun87@gmail.com";
const MIN_LENGTH = 8;

/** 입력이 터미널에 에코되지 않도록 가린다. */
function askHidden(question: string): Promise<string> {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const output = rl as unknown as { output: NodeJS.WritableStream; _writeToOutput?: (s: string) => void };
    let first = true;
    output._writeToOutput = function (stringToWrite: string) {
      if (first) {
        output.output.write(stringToWrite);
        first = false;
        return;
      }
      // 프롬프트 이후 입력은 전부 삼킨다.
      if (stringToWrite.includes("\n")) output.output.write("\n");
    };
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function main() {
  // 비밀번호를 가려 받으려면 진짜 터미널이 필요하다. Claude Code의 `!` 실행이나
  // 파이프로 들어오면 stdin이 TTY가 아니라서 프롬프트가 빈 값으로 떨어진다 —
  // 조용히 실패하지 않도록 먼저 걷어낸다.
  if (!process.stdin.isTTY) {
    console.error(
      "이 스크립트는 터미널에서 직접 실행해야 합니다(비밀번호를 가려 받기 위함).\n" +
        "  Terminal.app 등에서: cd " +
        path.join(__dirname, "..", "..") +
        " && npx tsx web/scripts/set-password.ts\n" +
        "터미널을 쓰기 어렵다면 로그인 후 앱에서 설정 → 계정 → 비밀번호 저장을 쓰세요.",
    );
    process.exit(1);
  }

  const email = process.argv[2] ?? DEFAULT_EMAIL;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    console.error("NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY가 web/.env.local에 없습니다.");
    process.exit(1);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: list, error: listError } = await admin.auth.admin.listUsers();
  if (listError) {
    console.error("사용자 조회 실패:", listError.message);
    process.exit(1);
  }
  const user = list.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
  if (!user) {
    console.error(`${email} 계정을 찾지 못했습니다.`);
    process.exit(1);
  }

  console.log(`대상 계정: ${email}`);
  const password = await askHidden(`새 비밀번호 (${MIN_LENGTH}자 이상): `);
  if (password.length < MIN_LENGTH) {
    console.error(`\n${MIN_LENGTH}자 이상이어야 합니다.`);
    process.exit(1);
  }
  const confirm = await askHidden("한 번 더: ");
  if (password !== confirm) {
    console.error("\n두 번 입력한 비밀번호가 다릅니다.");
    process.exit(1);
  }

  const { error } = await admin.auth.admin.updateUserById(user.id, { password });
  if (error) {
    console.error("\n설정 실패:", error.message);
    process.exit(1);
  }
  console.log("\n완료. 이제 /login에서 이메일+비밀번호로 바로 로그인됩니다.");
}

main();
