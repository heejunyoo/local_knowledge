"use client";

import { useEffect } from "react";

export function ServiceWorkerRegister() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // 등록 실패는 조용히 무시 — PWA 오프라인 셸은 향상 기능이지 필수 경로가 아님.
      });
    }
  }, []);
  return null;
}
