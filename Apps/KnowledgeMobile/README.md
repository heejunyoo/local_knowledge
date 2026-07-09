# Knowledge Mobile (iOS)

Thin SwiftUI client for **Personal Core** on Mac mini (Tailscale).

Normative API: [`docs/core_platform_sketch.md`](../../docs/core_platform_sketch.md)

## Free Apple ID (no $99)

1. Mac: `scripts/mobile-gateway.sh` 또는 `knowledged --http-port 8741 --pair`  
   (또는 Knowledge.app 설정 → **모바일 연결** → 페어링 코드)
2. Xcode로 `KnowledgeMobile.xcodeproj` 열기
3. Signing: **Personal Team** 선택 + Bundle ID 고유화  
   (`local.knowledge.mobile.<yourname>`)
4. iPhone 연결 → Run
5. 앱: Core URL = `http://100.x.y.z:8741` + 6자리 코드

> Free provisioning은 약 **7일**마다 재설치가 필요할 수 있음. 데이터는 Mac에 있음.

## Open project

```bash
open Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj
```

## Files

| File | Role |
|------|------|
| `Sources/KnowledgeMobileApp.swift` | entry + tabs |
| `Sources/CoreClient.swift` | pairing · RPC · chat · review |
| `Sources/ContentViews.swift` | Home / Ask / Search / Review / Settings |
| `Info.plist` | ATS local networking for Tailscale HTTP |

## Tabs (M2/M3)

- **홈** — 연결 상태 · 확인함 개수  
- **물어보기** — `ask.fast` → `/v1/chat` progressive  
- **검색** — `knowledge.search`  
- **확인함** — `knowledge.review.list` / `.accept`  
- **설정** — URL · 서버 revoke  

## Network / ATS

Core uses **HTTP** on Tailscale (`http://100.x.x.x:8741`).  
`Info.plist` sets `NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking` (Tailscale 100.x is not always “local” to ATS).

After changing Info.plist: Xcode **Product → Clean Build Folder**, delete app from iPhone, **Run** again.

If you still see *App Transport Security policy requires secure connection*, the installed build is stale — reinstall from Xcode.
