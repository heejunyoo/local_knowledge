# Personal Core Platform — 완전 스케치 (Normative)

| Field | Value |
|-------|--------|
| Date | 2026-07-09 |
| Status | **Normative** — M0–M4 구현 (M5 HTTPS/푸시 이후) |
| Network | Tailscale (개인 mesh) 필수 권장 |
| Auth | Device pairing token (`Authorization: Bearer`) |
| SoT | 서비스별 (Core는 라우터·인증만 — **데이터 SoT 아님**) |
| Port | `8741` (Core HTTP) · Diet 예약 `8751` |
| Repo paths | `Packages/KnowledgeGateway` · `Apps/KnowledgeMobile` · `knowledged --http-port` |

---

## 0. 한 줄 원칙

> **Tailscale로 신뢰 네트워크를 만들고, Core 게이트웨이가 여러 개인 서비스(Knowledge, Diet, …)를 라우팅·인증·통합 챗으로 묶는다.**  
> iOS 네이티브 앱은 Core에만 붙는 **얇은 클라이언트**다. 녹음·인덱스·7B·vault 커밋은 Mac에 남긴다.

| 원칙 | 내용 |
|------|------|
| Single SoT per domain | Knowledge vault / Diet DB는 각자 Mac 디스크 |
| Core is not a dump | 본문·식단 전문을 Core DB에 쌓지 않음 |
| Cloud free first | 생성 경로: 클라우드 free → (옵션) 7B → extractive |
| Progressive UX | 빠른 근거 답 → AI 다듬기 (모바일·데스크톱 동일) |
| Free Apple ID OK | Personal Team 설치 가능 (7일 재서명 트레이드오프) |

---

## 1. 시스템 다이어그램

```
                         Tailscale mesh (encrypted trust fabric)
        ─────────────────────────────────────────────────────────
        iPhone                              Mac mini (always-on)
   ┌──────────────────┐              ┌────────────────────────────────┐
   │ Knowledge Mobile │   HTTP JSON  │  Core Gateway  :8741           │
   │ SwiftUI thin     │─────────────►│  GET  /v1/health               │
   │ Keychain token   │   Bearer     │  POST /v1/pair/*               │
   └──────────────────┘              │  POST /v1/rpc   (JSON-RPC 2.0) │
                                     │  POST /v1/chat  (orchestrate)  │
                                     │           │                    │
                                     │    ┌──────┴───────┐            │
                                     │    ▼              ▼            │
                                     │ Knowledge      Diet F/U        │
                                     │ inproc         http :8751      │
                                     │ knowledged     (future)        │
                                     │ SQLite+vault   SQLite          │
                                     └────────────────────────────────┘
                                              ▲
                                              │ Unix domain socket
                                              │ (desktop app local)
                                     ┌────────┴────────┐
                                     │ Knowledge.app   │
                                     │ (macOS SwiftUI) │
                                     └─────────────────┘
```

**제품 기본 경로:** App → Core only.  
**직호출:** 디버그/내부 서비스 포트 허용 (제품 UX에는 노출하지 않음).

---

## 2. 계층 책임

| 층 | 책임 | 하지 않는 것 |
|----|------|----------------|
| **Tailscale** | 기기 식별·암호화 터널·집 밖 접속 | 앱 ACL, 비즈니스 로직 |
| **Core Gateway** | 페어링, Bearer, method 라우팅, 통합 챗, 최소 감사 | vault/식단 본문 SoT |
| **Domain service** | SoT, 도메인 API, 분석·인덱스 | 타 도메인 데이터 소유 |
| **macOS App** | 녹음(SCK), 리뷰 UX, 설정, 로컬 UDS | 폰에 무거운 모델 배포 |
| **iOS App** | 페어링, 검색, 질문, 확인함, 설정 | 전체 코퍼스 인덱싱·7B |

---

## 3. 페어링 시퀀스

```
iPhone                         Core (:8741)                    Mac UI / CLI
  |                                |                               |
  |                                |◄── POST /v1/pair/start ───────|  (local)
  |                                |── {code: "482910", 300s} ────►|
  |── POST /v1/pair/complete ─────►|                               |
  |   {code, device_name}          |                               |
  |◄─ {token, device_id, core} ────|  (hash only on disk)          |
  |  store token (UserDefaults/Keychain)                           |
  |── Authorization: Bearer … ────►|  all subsequent calls         |
  |── POST /v1/pair/revoke ───────►|  token invalidated            |
```

| 규칙 | 값 |
|------|-----|
| 코드 | 6자리 숫자, **1회용**, TTL **300s** |
| 토큰 | 32B random → base64url, 디스크에는 **SHA-256 해시만** |
| 저장 경로 | `~/Knowledge/config/mobile_devices.json` (mode `0600`) |
| pair/start | 제품상 Mac 로컬에서만 호출 (원격 무차별 발급 방지 — M2 이후 loopback 제한 강화) |
| revoke | 해당 device 행 삭제 → 이후 401 |

---

## 4. Core HTTP API

### 4.1 Base

| Item | Value |
|------|--------|
| Base URL | `http://<mac-tailscale-ip>:8741` |
| M1 transport | Plain HTTP **on Tailscale only** (공인 포워딩 금지) |
| M5 | Optional HTTPS / 인증서 |
| Content-Type | `application/json; charset=utf-8` |
| Auth | `Authorization: Bearer <device_token>` (pair/complete·pair/start 제외) |

### 4.2 Endpoints

| Method | Path | Auth | Request | Response (200) |
|--------|------|------|---------|----------------|
| GET | `/v1/health` · `/health` | none | — | `{ ok, core, gateway, services, knowledge? }` |
| POST | `/v1/pair/start` | none (local) | `{}` | `{ code, expires_in, core_name }` |
| POST | `/v1/pair/complete` | none | `{ code, device_name }` | `{ token, device_id, core_name }` |
| GET | `/v1/pair/status` | Bearer | — | `{ ok, device_id, name, core_name }` |
| POST | `/v1/pair/revoke` | Bearer | `{}` | `{ revoked: true }` |
| POST | `/v1/rpc` | Bearer | JSON-RPC 2.0 | JSON-RPC result/error |
| POST | `/v1/chat` | Bearer | `{ message, mode? }` | `{ answer, engine, sources, trace }` |

**HTTP 상태**

| Code | 의미 |
|------|------|
| 200 | 성공 (JSON-RPC 앱 에러도 envelope 200 + `error` 객체일 수 있음) |
| 400 | 페어링 코드 오류·만료·bad JSON |
| 401 | 토큰 없음/무효/revoke |
| 404 | 알 수 없는 path |
| 500 | 서버 예외 |

### 4.3 JSON-RPC (`POST /v1/rpc`)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "knowledge.search",
  "params": { "q": "결제 API", "limit": 10 }
}
```

#### Method registry

| Method | Service | Params (요지) | Result (요지) |
|--------|---------|---------------|---------------|
| `core.ping` | Core | — | `{ pong: true }` |
| `core.health` | Core | — | health 객체 |
| `core.services` | Core | — | `{ knowledge, diet }` |
| `knowledge.health` | Knowledge | — | daemon health |
| `knowledge.search` | Knowledge | `q`, `limit?` | hits (FTS/hybrid) |
| `knowledge.ask` | Knowledge | `q`/`question`, `limit?`, `use_llama?` | `{ answer, engine, citations }` progressive |
| `knowledge.ask.fast` | Knowledge | `q`, `limit?` | extractive only (목표 &lt;2s) |
| `knowledge.meetings` | Knowledge | `status?` | meeting 배열 |
| `knowledge.review.list` | Knowledge | — | `status=review_needed` 미팅 배열 |
| `knowledge.review.accept` | Knowledge | `id` (meeting) | vault commit 결과 |
| `diet.ping` | Diet | — | `{ ok, enabled }` |
| `diet.log_meal` | Diet | items, kcal?, protein_g? | meal |
| `diet.log_workout` | Diet | kind, minutes | workout |
| `diet.log_metric` | Diet | weight_kg?, sleep_h? | metric |
| `diet.day_summary` | Diet | — | day totals + lists |
| `diet.week_review` | Diet | — | 7-day bars |
| `diet.dashboard` | Diet | — | progress + analysis + goals |
| `diet.goals` / `diet.goals.set` | Diet | targets | goals |
| `diet.coach` | Diet | message? | analysis text |

미등록 method → JSON-RPC `-32601 Method not found`.

### 4.4 Integrated chat (`POST /v1/chat`)

```json
// request
{ "message": "오늘 운동 어때?", "mode": "auto" }

// response
{
  "answer": "...",
  "engine": "cloud/gemini-… | extractive | local-7b",
  "sources": [
    { "service": "knowledge", "title": "…", "snippet": "…", "unit_id": "…" }
  ],
  "trace": ["intent:knowledge", "knowledge.ask"]
}
```

| mode | 동작 |
|------|------|
| `auto` | 키워드 의도 분류 → 서비스 tool → 생성 |
| `knowledge` | Knowledge만 |
| `diet` | Diet만 (M4; 그 전 미구현 안내) |

**의도 키워드 (M1 규칙 기반, 이후 소형 LLM)**

- diet: 먹, 식사, 운동, 칼로리, 체중, 다이어트, 단백질, 수면…  
- knowledge: 미팅, 노트, 결정, 예전에, 회의, 요약…

**생성 cascade (서버 측, 데스크톱과 동일 철학)**  
1. retrieve (fast)  
2. cloud free (키 있을 때)  
3. local 7B (옵션, timeout 있음)  
4. extractive 폴백  

모바일 클라이언트는 **ask.fast → chat/refine** progressive UI를 권장.

---

## 5. 서비스 등록

파일: `~/Knowledge/config/core_services.json` (선택; 없으면 기본 knowledge inproc)

```json
{
  "version": 1,
  "core_name": "heejun-mac-mini",
  "http_port": 8741,
  "bind": "0.0.0.0",
  "services": {
    "knowledge": { "type": "inproc", "enabled": true },
    "diet": {
      "type": "http",
      "base_url": "http://127.0.0.1:8751",
      "enabled": false
    }
  }
}
```

| type | 의미 |
|------|------|
| `inproc` | 같은 프로세스 `PipelineService` / store |
| `http` | 사이드카 (dietd 등) — Core가 reverse proxy 역할 |

---

## 6. 보안

| 규칙 | 내용 |
|------|------|
| 네트워크 | **Tailscale IP만** 사용. 공인 포트 포워딩·UPnP 금지 |
| 토큰 | Bearer, 해시 저장, 기기별 revoke |
| Redaction | `knowledge.ask` / `chat` 클라우드 경로 = 데스크톱과 동일 preflight |
| 로그 | method, device_id, latency — **본문·토큰 원문 금지** |
| pair/start | **loopback-only** (Mac UI/CLI). 원격 Tailscale에서 코드 발급 불가 |
| ATS (iOS) | Tailscale HTTP 허용 (`NSAllowsLocalNetworking` / dev ATS) |

---

## 7. Diet F/U 확장 (스키마 스케치)

SoT 루트 후보: `~/Knowledge-diet/` 또는 `~/Knowledge/services/diet/` (별 SQLite).

| Entity | Fields (예) |
|--------|-------------|
| meal | id, ts, items[], kcal?, protein_g?, note |
| workout | id, ts, kind, minutes, intensity |
| metric | id, ts, weight_kg?, sleep_h? |
| goal | target_kcal, target_protein, weekly_workouts |

분석 API: **숫자 집계 먼저**, 문장은 그 위 LLM.  
Knowledge vault에 식단 전문을 넣고 검색만 하는 방식은 **비권장**.

---

## 8. iOS 정보 구조 (IA)

| Tab | 기능 | API |
|-----|------|-----|
| 홈 | 연결 상태, 확인함 배지, (diet on 시) 오늘 한 줄 | `/v1/pair/status`, `knowledge.review.list` |
| 물어보기 | progressive: 빠른 답 → AI 다듬기 | `knowledge.ask.fast` → `/v1/chat` |
| 검색 | 키워드 | `knowledge.search` |
| 확인함 | 카드 · 저장 | `knowledge.review.list` / `.accept` |
| 설정 | URL, 페어링, revoke | pair/* |

**비범위 v1:** 시스템 회의 녹음, 폰 7B, 전체 vault 양방향 싱크 UI.  
**v1.1 후보:** 음성 메모 인박스, Share Extension, Watch 배지.

### 설치 (Free Apple ID)

1. Mac: `scripts/mobile-gateway.sh` 또는 `knowledged --http-port 8741 --pair`  
2. Xcode: `Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj`  
3. Signing: **Personal Team** + unique Bundle ID (`local.knowledge.mobile.<name>`)  
4. iPhone Run → Core URL `http://100.x.y.z:8741` + 6자리 코드  
5. 약 **7일**마다 재서명/재설치 가능

---

## 9. Mac 측 진입점

| 진입 | 명령 / UI |
|------|-----------|
| CLI gateway + 코드 | `knowledged --http-port 8741 --pair` |
| 스크립트 | `scripts/mobile-gateway.sh` |
| 앱 설정 | **모바일 연결** 카드 → 페어링 코드 발급 (loopback `127.0.0.1:8741`) |
| 데스크톱 UDS | 기존 `cache/daemon.sock` 유지 (앱 로컬 전용) |

Gateway는 프로세스 수명 동안 **retain** 필수 (`mobileGateway` 보유 — 조기 deinit 버그 재발 금지).

---

## 10. 구현 웨이브

| ID | 산출 | 상태 |
|----|------|------|
| **M0** | 본 스케치 (normative) | ✅ |
| **M1** | Mac HTTP gateway + pairing + knowledge.* RPC + chat | ✅ |
| **M2** | iOS 스캐폴드 + Xcode 프로젝트 + 페어링/검색/물어보기 | ✅ |
| **M3** | 확인함 accept · 홈 배지 · Mac 페어링 UI | ✅ |
| **M4** | Diet inproc store + chat intent + day/week/coach | ✅ |
| **M5** | HTTPS · 푸시(유료 계정) · 실기기 E2E 필드 | 이후 |

---

## 11. 파일 맵 (구현 SoT)

| 경로 | 역할 |
|------|------|
| `docs/core_platform_sketch.md` | 이 문서 (규범) |
| `docs/mobile_plan.md` | 모바일 UX/웨이브 (실행 계획) |
| `Packages/KnowledgeGateway/` | `MobileHTTPServer`, `PairingStore` |
| `Sources/knowledged/main.swift` | `--http-port` / `--pair` |
| `Apps/KnowledgeMobile/` | iOS SwiftUI 클라이언트 |
| `scripts/mobile-gateway.sh` | 필드 기동 |
| `~/Knowledge/config/mobile_devices.json` | 페어링 기기 (런타임) |

---

## 12. 비목표

- Core에 전 서비스 데이터 몰아넣기  
- 공인 인터넷 노출 / 팀 멀티테넌트 SaaS  
- 폰에서 7B 로컬 추론  
- WebView-only “웹앱”을 제품 1순위로 삼기 (네이티브 우선)  

---

## 13. 성공 기준

| # | 기준 | 검증 |
|---|------|------|
| 1 | Tailscale 상 `GET /v1/health` 또는 `core.ping` | curl |
| 2 | 페어링 1회 → Bearer 발급 | pair start/complete |
| 3 | `knowledge.search` / `knowledge.ask.fast` &lt; ~2s | curl / iOS |
| 4 | iOS 실기기 또는 시뮬에서 검색·질문 | Manual |
| 5 | revoke 후 401 | curl |
| 6 | Mac 설정에서 6자리 코드 표시 | UI |

### curl 스모크 (필드)

```bash
# health
curl -sS "http://127.0.0.1:8741/v1/health"

# pair
CODE=$(curl -sS -X POST "http://127.0.0.1:8741/v1/pair/start" | python3 -c "import sys,json;print(json.load(sys.stdin)['code'])")
TOK=$(curl -sS -X POST "http://127.0.0.1:8741/v1/pair/complete" \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"$CODE\",\"device_name\":\"smoke\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# ask.fast
curl -sS -X POST "http://127.0.0.1:8741/v1/rpc" \
  -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"knowledge.ask.fast","params":{"q":"스모크","limit":3}}'
```

---

## 14. 변경 정책

- API 파괴 변경은 `gateway` 버전 bump + 이 문서 갱신.  
- method 추가는 registry 표에 먼저 기록 후 구현.  
- Diet 등 신규 서비스는 **별 프로세스 + SoT** 후 Core 등록만.

---

*Normative sketch · M1 done · M2/M3 mobile in progress.*
