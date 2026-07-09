# Mobile ATS 장애 — 재분석 (2026-07-10)

시험이 아니라 **원인 규명**. 폰 재설치를 반복하게 만든 책임은 수정 루프에 있음.

---

## 1. 증상

iOS 앱에서 Core URL `http://100.x.x.x:8741` 연결 시:

> The resource could not be loaded because the App Transport Security policy requires the use of a secure connection

---

## 2. 타임라인 (팩트)

| 시각(대략) | 상태 |
|------------|------|
| 게이트웨이 Mac | `:8741` health OK (loopback + Tailscale IP) |
| Info.plist | `NSAllowsArbitraryLoads=true` 넣음 |
| DerivedData **iphoneos** 빌드 00:13 | Info.plist에 ATS 키 **존재** 확인 |
| 사용자 | **동일 ATS 에러 지속** |
| CleartextHTTP (NWConnection) 소스 | **00:15** 작성 |
| 기기 빌드 바이너리 | **00:13** → CleartextHTTP **미포함** |

→ 사용자가 여러 번 지우고 깐 빌드는 **URLSession + 잘못된 ATS 조합**이었고,  
**Network.framework 우회 수정은 폰에 한 번도 안 올라간 상태**일 가능성이 큼.

---

## 3. 근본 원인 (가장 유력)

### A. Info.plist 자기모순 (핵심)

당시 Info.plist:

```xml
NSAllowsArbitraryLoads = true
NSAllowsLocalNetworking = true
NSAllowsArbitraryLoadsInWebContent = true   <!-- 문제 -->
```

Apple ATS 규칙 (요약):

- `NSAllowsArbitraryLoadsInWebContent` / `ForMedia` 등이 **있으면**,  
  **`NSAllowsArbitraryLoads`가 URLSession에 대해 무시**될 수 있음.
- `InWebContent` 는 **WKWebView 쪽만** 예외이고,  
  **`URLSession`(앱 API 호출) 보안은 그대로** 유지하는 키.

즉 “HTTP 허용했다”고 넣은 키가 오히려  
**URLSession cleartext를 계속 막게** 만들었을 수 있다.

### B. 통신 스택

당시 앱 코드: **URLSession.shared** → ATS 적용 대상.

### C. 프로세스

ATS 실패 → Info.plist 패치 → “삭제 후 재설치” 반복.  
원인 A를 못 잡고 키만 추가해서 **같은 클래스 에러 재발**.

---

## 4. 수정 (코드베이스, 이미 반영 방향)

| 층 | 조치 | 목적 |
|----|------|------|
| Info.plist | `InWebContent` **제거**. `ArbitraryLoads` + `LocalNetworking` 만 | URLSession ATS 정상 해제 |
| CoreClient | HTTP는 **NWConnection TCP** (`CleartextHTTP`) | URLSession ATS 경로 자체 회피 |
| Mac 게이트웨이 | pair 전 `ensureMobileGateway` | “게이트웨이 없음” 재발 방지 |
| 버전 | 0.1.3 / build 5 | 설치본 식별 |

**이중 방어:** plist가 또 꼬여도 NW 경로면 ATS 문구가 나오지 않아야 함.

---

## 5. 남은 위험 (정직하게)

폰을 **한 번** 0.1.3으로 올린 뒤에도 가능한 실패 (ATS **아님**):

| 위험 | 확률 | 증상 | 대응 |
|------|------|------|------|
| Tailscale off / 다른 tailnet | 중 | 타임아웃·연결 실패 | Mac·폰 Tailscale ON |
| Mac 게이트웨이 down | 중 | 연결 실패 | 앱 설정 모바일 연결 / ensureMobileGateway |
| 페어링 코드 만료 | 중 | pair failed | Mac에서 새 코드 |
| Free Apple ID 7일 | 낮~중 | 앱 실행 안 됨 | 재서명 (연결 문제와 별개) |
| CleartextHTTP 파서 버그 | 낮 | 파싱 에러 | 로그 보고 수정 |
| **동일 ATS 영문 문구** | **0.1.3 이후 기대치 낮음** | — | 나오면 즉시 스택 재조사 |

**“에러가 절대 없다”고 약속할 수 있는 상태는 아님.**  
다만 **같은 ATS 루프를 또 도는 설계 결함**은 위 A+B로 설명·차단 가능.

---

## 6. 권장 진행 방식 (사용자 부담 최소)

1. **지금은 폰 안 건드려도 됨.** Mac Knowledge(식단·지식)는 독립적으로 사용 가능.  
2. 모바일은 **원인 수정이 코드에 들어간 뒤**, 사용자가 준비됐을 때 **한 번만** 설치:  
   - 목표 버전 **0.1.3 (5)**  
   - 가능하면 삭제 없이 Run 덮어쓰기 시도 → 안 되면 그때만 삭제  
3. 성공 기준 (한 번에 끝):  
   - 페어링 성공 **또는**  
   - 실패 시 **ATS 영문이 아닌** 다른 메시지 (타임아웃/코드 오류 등)

---

## 7. 교훈 (에이전트)

- ATS 관련 키를 “많이 넣을수록” 좋아지지 않음. **InWebContent와 ArbitraryLoads 동시 설정 금지.**  
- 폰 재설치를 디버그 수단으로 쓰지 말 것.  
- 기기 빌드 시각 vs 소스 수정 시각을 먼저 대조할 것.

---

*Document only — no requirement to reinstall until owner chooses.*
