# Knowledge 모바일 경험 — 실행 계획

| Field | Value |
|-------|--------|
| Date | 2026-07-09 |
| Status | **Active** — M1–M4 ✅ · M5 실기기 E2E |
| Normative parent | [`core_platform_sketch.md`](./core_platform_sketch.md) |
| Constraint | 시스템 오디오·로컬 7B·전체 인덱싱은 **Mac mini 전용** |

---

## 0. 결론

모바일에서 Mac과 동일한 풀 챗(7B 로딩 + 전체 코퍼스 인덱싱)은 불필요하다.

> **Mac mini = 지식 엔진 (SoT · 인덱스 · 무거운 생성)**  
> **iPhone = 얇은 클라이언트 (읽기 · 질문 · 확인 · 페어링)**

→ Tailscale + Core Gateway 로 **네이티브 iOS 챗이 성립**한다. (웹앱 비1순위)

---

## 1. 아키텍처 (요약)

상세 시퀀스·API·보안은 **Core 스케치**가 SoT.

```
iOS thin  ──Bearer──►  Core :8741  ──inproc──►  Knowledge (SQLite + vault)
                         │
                         └──future──►  Diet :8751
```

---

## 2. 왜 폰에서 “그대로”는 힘든가

| 기능 | 모바일 | 이유 |
|------|--------|------|
| SCK 시스템 오디오 | ❌ | macOS API |
| 로컬 7B | ❌ | 열·배터리·스토리지 |
| 전체 코퍼스 인덱싱 | △ | Mac과 이중 인덱스 위험 |
| 질문·검색·확인함 | ✅ | Core API만 있으면 됨 |
| 짧은 음성 메모 | ✅ v1.1 | iOS Speech → Mac inbox |

---

## 3. 웨이브 상태

| Wave | 산출 | 상태 |
|------|------|------|
| **M0** | Core 스케치 + 모바일 계획 | ✅ |
| **M1** | gateway + pairing + knowledge RPC + chat | ✅ |
| **M2** | iOS: 연결·검색·물어보기 + Xcode 프로젝트 | ✅ |
| **M3** | 확인함 accept · 배지 · Mac 페어링 UI | ✅ |
| **M4** | Diet inproc + chat intent | ✅ |
| **M5** | HTTPS · 푸시 · 실기기 Tailscale E2E | 이후 |

---

## 4. iOS 화면 (v1)

| 화면 | 내용 | 상태 |
|------|------|------|
| 페어링 | Core URL + 6자리 코드 | ✅ 소스 |
| 홈 | 연결 상태 · 확인함 배지 | 🚧 배지 |
| 물어보기 | progressive fast → chat | ✅ 소스 |
| 검색 | `knowledge.search` | ✅ 소스 |
| 확인함 | list / accept | 🚧 |
| 설정 | URL · 상태 · revoke(서버) | 🚧 revoke API |

**비범위 v1:** 회의 녹음, 전체 Obsidian 동기화 UI, 오프라인 풀 인덱스.

---

## 5. Mac 측

| 항목 | 방법 |
|------|------|
| 게이트웨이 기동 | `scripts/mobile-gateway.sh` |
| 페어링 코드 | `--pair` stderr 또는 **설정 → 모바일 연결** |
| 생성 정책 | cloud free 우선 · progressive · 7B 옵션 |

---

## 6. 보안 (요약)

- Tailscale only · 공인 노출 금지  
- 토큰 해시 저장 · revoke  
- 모바일 ask/chat 에도 redaction preflight (서버)  
- Free Apple ID 7일 재서명 고지  

---

## 7. 챗을 쓸 만하게

1. **즉시** 근거 모음 (`knowledge.ask.fast`)  
2. **이어서** `/v1/chat` 또는 refine (cloud free)  
3. 7B는 Mac 옵션 — 폰에서 돌리지 않음  

---

## 8. 필드 체크리스트 (지금)

- [x] Core 스케치 normative  
- [x] gateway curl smoke (pair + ask.fast + review.list + revoke 401)  
- [x] iOS 소스 (페어링 · 검색 · 물어보기 · 확인함 · 설정 revoke)  
- [x] Xcode 프로젝트 (`Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj`) · simulator build OK  
- [x] Mac 설정 **모바일 연결** 페어링 코드 UI  
- [x] 확인함 accept API + UI  
- [x] Daemon 기본 `--http-port 8741`  
- [x] pair/start loopback-only  
- [x] Diet M4 inproc + chat intent  
- [ ] Personal Team으로 실기기 설치 (Xcode Signing)  
- [ ] 실기기 Tailscale E2E  

---

*Execute against core_platform_sketch.md.*
