# Knowledge Field — 타 Mac 설치 (no admin)

Admin / sudo / 시스템 LaunchDaemon **없음**.  
외부 Heejun/서버 **없음**.

## 필요 조건

| 항목 | 내용 |
|------|------|
| Mac | Apple Silicon, macOS 14+ |
| 도구 | Xcode 또는 CLT (`xcode-select --install`) |
| 서명 | 로그인 키체인에 **Apple Development** 인증서 (Xcode → Settings → Accounts) |
| 데이터 경로 | `~/Knowledge`, vault 기본 `~/Obsidian/Main` |

## 설치

```bash
git clone <repo> ~/IdeaProjects/KnowledgeApp   # 또는 소스 복사
cd ~/IdeaProjects/KnowledgeApp
./scripts/bootstrap-knowledge-root.sh
# vault_path 확인/수정
$EDITOR ~/Knowledge/config/app.json
./scripts/package-app.sh
open ~/Applications/Knowledge.app
```

## 권한 (1회)

시스템 설정 → 개인정보 보호 및 보안:

1. **화면 기록** → Knowledge 허용  
2. **음성 인식** → Knowledge 허용  

동일 Development identity로 재설치하면 보통 **재허용 불필요**.

## 검증 (사람 클릭 없이)

```bash
./scripts/verify-field.sh
```

## Field 루프

1. 회의/동영상 **소리 재생** 중 → 앱에서 **녹음 시작** → **끝내기**  
2. 받아쓰기·요약 후 **확인 필요**  
3. **확인 후 저장** → `{vault}/Meetings/YYYY/MM/{id}.md`  
4. 홈 **검색**으로 저장된 미팅 FTS  

## Degrade (툴 없어도 동작)

| 기능 | 기본 | 툴 있을 때 |
|------|------|------------|
| ASR | Apple Speech (UI) | whisper.cpp under `~/Knowledge/tools/…` |
| 요약·물어보기 | **클라우드 무료 티어** (Gemini→Groq→OpenRouter) → 로컬 **7B** → extractive | `config/llm_providers.json` 으로 모델 교체 |

툴 설치:

```bash
./scripts/install-tool-file.sh /path/to/whisper-cli tools/whisper.cpp/1.7.5/whisper-cli
./scripts/install-tool-file.sh /path/to/model.bin tools/models/whisper/ggml-large-v3-turbo.bin
# pin sha256 in ~/Knowledge/config/tools_manifest.json
./scripts/verify-tools.sh
```

## 하지 말 것

- `swift run` / 터미널 바이너리로 제품 권한 검증 (TCC 다른 클라이언트)
- `codesign -s -` ad-hoc 재서명으로 배포 (CDHash 붕괴)
- admin 전역 데몬 강제 설치
