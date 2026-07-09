# API minimum versions

Deployment target: **macOS 14.0+**.

| API / feature | Min macOS | Notes |
|---------------|-----------|--------|
| ScreenCaptureKit + `capturesAudio` | 13.0 | Online meeting system audio |
| `excludesCurrentProcessAudio` | 13.0 | Avoid self-feedback |
| `SMAppService` | 13.0 | LaunchAgent registration preferred |
| SwiftUI `MenuBarExtra` | 13.0 | Menu bar recorder |
| Apple Foundation Models | 26.0 | Optional future LLM path; not MVP |
| App Sandbox + SCK + broad AE | N/A | Personal build is **non-sandboxed** (KD-19) |
