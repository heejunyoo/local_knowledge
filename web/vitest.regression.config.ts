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
  },
});
