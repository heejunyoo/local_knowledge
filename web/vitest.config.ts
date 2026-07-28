import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
  test: {
    include: ["tests/domain/**/*.test.ts", "tests/regression/**/*.test.ts"],
    environment: "node",
  },
});
