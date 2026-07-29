import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // web/lib/redaction.ts·web/lib/llm/catalog.ts가 리포 루트(docs/, config/)의
  // JSON을 정적 import한다(SoT 중복 방지) — Turbopack이 프로젝트 루트를
  // web/으로 자동 추론하면 그 밖의 파일 import를 "Module not found"로
  // 거부한다. 리포 루트를 명시해 해결한다.
  turbopack: {
    root: path.join(__dirname, ".."),
  },
};

export default nextConfig;
