import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
  test: {
    // 회귀 스위트(tests/regression)는 실제 Supabase 프로젝트가 필요해 별도
    // 스크립트(npm run test:regression)로만 돌린다. 기본 `npm run test`는
    // 순수 도메인 유닛 테스트만 — 오프라인/CI에서도 항상 통과해야 한다.
    include: ["tests/domain/**/*.test.ts"],
    environment: "node",
  },
});
