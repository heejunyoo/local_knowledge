// PWA 오프라인 셸 전용 서비스워커. 데이터(HTML 페이지·API 응답)는 캐시하지
// 않는다 — 단일 사용자 앱에서 stale 데이터가 오프라인 미표시보다 더
// 위험하다(액션플랜 §P5). 캐시 대상은 정적 앱 셸(아이콘·오프라인 안내)뿐.
const SHELL_CACHE = "knowledge-shell-v1";
const SHELL_ASSETS = ["/offline.html", "/icons/icon-192.png", "/icons/icon-512.png", "/manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL_ASSETS)).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL_CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  // 페이지 내비게이션만 오프라인 폴백 대상. API·정적 자산은 항상 네트워크로
  // 통과시켜 데이터가 캐시에 고이지 않게 한다.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() => caches.match("/offline.html").then((res) => res ?? Response.error())),
    );
  }
});
