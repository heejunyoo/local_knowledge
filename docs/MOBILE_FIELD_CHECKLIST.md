# Mobile Field 체크리스트 — Mac Core + iPhone

| Field | Value |
|-------|--------|
| Date | 2026-07-09 |
| Scope | Personal Team · free Apple ID · Tailscale |
| Normative | [`core_platform_sketch.md`](./core_platform_sketch.md) |
| Package | `~/Applications/Knowledge.app` |

---

## 0. 한 번에 준비 (Mac)

```bash
cd ~/IdeaProjects/KnowledgeApp
./scripts/bootstrap-knowledge-root.sh   # 최초 1회
./scripts/package-app.sh                # 서명 설치
open ~/Applications/Knowledge.app
```

앱이 `knowledged`를 띄우며 **기본 `--http-port 8741`** 포함.

게이트웨이만 단독:

```bash
./scripts/mobile-gateway.sh
# 또는 스모크
./scripts/verify-mobile.sh
```

---

## 1. Mac 쪽 자동 검증 (클릭 최소)

| # | 확인 | 방법 | 기대 |
|---|------|------|------|
| M1 | 앱 설치·서명 | `codesign -dv ~/Applications/Knowledge.app` | Apple Development |
| M2 | 게이트웨이 health | `./scripts/verify-mobile.sh` | `SMOKE_OK` |
| M3 | pair start loopback | verify-mobile | 코드 6자리 |
| M4 | ask.fast | verify-mobile | answer 비어 있지 않음 |
| M5 | diet intent | verify-mobile | meal/workout 기록 |
| M6 | revoke → 401 | verify-mobile | unauthorized |

---

## 2. Mac UI 수동

| # | 항목 | 확인 |
|---|------|------|
| U1 | 홈 로드 · 백엔드 연결 | 상태 정상 |
| U2 | **설정 → 모바일 연결** | Core URL 힌트 + **페어링 코드 만들기** |
| U3 | 코드 6자리 · 복사 | 5분 유효 |
| U4 | (선택) Tailscale IP | `http://100.x.y.z:8741` 형태 |

**Tailscale**

- Mac·iPhone 모두 같은 tailnet 로그인  
- Mac IP: Tailscale 메뉴 또는 앱 설정에 표시되는 Core URL  
- CLI가 있으면: `/Applications/Tailscale.app/...` 또는 `tailscale ip -4`  
- **공인 포트 포워딩 금지**

---

## 3. iPhone 설치 (Free / Personal Team)

1. Mac에서 Xcode 열기:
   ```bash
   open ~/IdeaProjects/KnowledgeApp/Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj
   ```
2. Signing & Capabilities  
   - Team: **Personal Team** (Apple ID)  
   - Bundle ID: `local.knowledge.mobile.<고유이름>` (충돌 시 변경)
3. iPhone USB 연결 → Trust  
4. iPhone: 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 **신뢰**  
5. Xcode → Run (실기기)

> Free provisioning: 약 **7일**마다 재서명/재설치 가능. **데이터는 Mac**에 있음.

---

## 4. 페어링 E2E

| # | 단계 | 기대 |
|---|------|------|
| P1 | Mac 설정에서 코드 발급 | 6자리 표시 |
| P2 | iPhone: Core URL = `http://<mac-tailscale-ip>:8741` | |
| P3 | 코드 + 기기 이름 → 연결 | 홈 탭, 연결됨 점 |
| P4 | 홈 새로고침 | Core 이름 · 확인함 수 |

실패 시:

| 증상 | 조치 |
|------|------|
| 연결 시간 초과 | Mac·폰 Tailscale 동일 계정, Mac 방화벽, 게이트웨이 8741 listen |
| unauthorized / re-pair | 코드 만료 → Mac에서 새 코드 |
| pair/start 403 (폰에서) | 정상 — 코드는 Mac에서만 발급 |
| ATS / cleartext | Info.plist 에 local networking 허용됨 — URL 이 `http://` 인지 확인 |

---

## 5. 기능 E2E (폰)

| # | 기능 | 확인 |
|---|------|------|
| F1 | **검색** | 키워드 → 히트 또는 “결과 없음” |
| F2 | **물어보기** | 빠른 답 → (가능 시) AI 다듬기 |
| F3 | **확인함** | Mac에 review_needed 있으면 목록 · 저장 |
| F4 | 식단 문장 | “점심 샐러드 400kcal” → 기록 답 |
| F5 | 운동 문장 | “운동 걷기 20분” → 기록 답 |
| F6 | 홈 식단 줄 | day summary 한 줄 |
| F7 | 설정 → 페어링 해제 | 페어링 화면 복귀 · 재연결 시 새 코드 |

---

## 6. Mac·폰 연동 품질

| # | 항목 | 확인 |
|---|------|------|
| Q1 | 폰 검색 결과가 Mac 검색과 같은 코퍼스 | |
| Q2 | 확인함 저장 후 Mac vault에 노트 | |
| Q3 | diet.json 갱신 | `~/Knowledge/services/diet/diet.json` |
| Q4 | 앱 재실행 후에도 게이트웨이 유지 | daemon detach |

---

## 7. 보안 최소 확인

- [ ] Tailscale 외 공인 IP로 8741 노출 안 함  
- [ ] `mobile_devices.json` 권한 600  
- [ ] revoke 후 옛 토큰 401  
- [ ] pair/start 는 127.0.0.1 에서만  

---

## 8. 완료 정의 (Field ship)

- [x] package-app 설치  
- [x] verify-mobile.sh 자동 스모크  
- [ ] iPhone Personal Team Run 1회  
- [ ] 페어링 + 검색/물어보기 1회  
- [ ] (권장) 식단 기록 1회  

자동 스모크가 통과해도 **실기기 Tailscale 1회**는 오너 클릭이 필요합니다.

---

*After checklist: commit notes in DOGFOOD if new field observations.*
