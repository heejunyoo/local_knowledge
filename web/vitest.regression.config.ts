import { defineConfig } from "vitest/config";
import path from "node:path";

// tests/domain(vitest.config.ts)과 분리된 별도 설정 — include 글롭이 달라야
// `npm run test`(오프라인·CI 안전)와 `npm run test:regression`(실 Supabase
// 프로젝트 필요)가 서로의 스코프를 침범하지 않는다.
export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
  test: {
    include: ["tests/regression/**/*.test.ts"],
    environment: "node",
    testTimeout: 20000,
    // 회귀 파일이 2개 이상이 되면서(P4a-9) 각 파일이 독립적으로
    // test-client.ts의 매직링크 인증을 실행해 같은 오너 이메일로 동시에
    // generateLink를 호출 — 나중 호출이 앞선 링크를 무효화해 verifyOtp가
    // "invalid or expired"로 실패하는 경쟁 상태가 생겼다. 회귀 스위트는
    // 파일 수가 적고 인증 자체가 무거운 작업이 아니므로 직렬 실행으로 고정.
    fileParallelism: false,
  },
});
