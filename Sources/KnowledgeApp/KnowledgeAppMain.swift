import SwiftUI
import AppKit
import Speech
import AVFoundation
import KnowledgeUI
import KnowledgeCore

/// Ensures the process is a regular UI app when launched as a naked SPM binary
/// (MenuBarExtra-only apps are often invisible without a .app bundle).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid dying on SIGPIPE when launched under pipes / CI wrappers.
        signal(SIGPIPE, SIG_IGN)
        // Show Dock + allow windows. Menu bar still works.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Pre-flight permissions so first record isn't a silent fail
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { status in
            fputs("speech auth raw=\(status.rawValue)\n", stderr)
        }
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
        fputs("Knowledge UI ready — window should be frontmost.\n", stderr)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running for menu bar; user quits via menu.
        false
    }
}

@main
struct KnowledgeAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(
        knowledgeRoot: KnowledgePaths.defaultKnowledgeRoot
    )

    var body: some Scene {
        // Always-visible main window (fixes "swift run 했는데 아무 변화 없음")
        WindowGroup("Knowledge") {
            RootShellView(model: model)
        }
        .defaultSize(width: 480, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("캡처") {
                Button(model.isRecording ? "녹음 끝내기" : "녹음 시작") {
                    if model.isRecording {
                        model.stopRecording()
                    } else {
                        model.startRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("확인함 열기") {
                    // Focus main window — user switches to 확인함 tab manually if needed
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            RootShellView(model: model)
                .frame(width: 400, height: 600)
        } label: {
            MenuBarLabel(
                isRecording: model.isRecording,
                badge: model.reviewCount + model.failedCount + model.dueActionCount,
                statusLine: menuBarStatusLine
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            ZStack {
                TossColor.grey50.ignoresSafeArea()
                VStack(alignment: .leading, spacing: TossSpace.x4) {
                    Text("설정")
                        .font(TossFont.title())
                        .foregroundStyle(TossColor.grey900)
                    Text("지식 루트")
                        .font(TossFont.section())
                    Text(model.knowledgeRoot.path)
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.grey700)
                        .textSelection(.enabled)
                    Text(model.healthOK
                         ? "백그라운드 준비됨"
                         : model.connectionCaption)
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey700)
                    Text("백그라운드 엔진은 앱이 자동으로 켜요. 터미널 작업은 필요 없어요.")
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
                .padding(TossSpace.x6)
            }
            .frame(width: 360, height: 260)
        }
    }

    /// Compact one-liner for menu bar (review / diet summary).
    private var menuBarStatusLine: String {
        if model.isRecording { return "녹음" }
        if model.reviewCount > 0 { return "확인 \(model.reviewCount)" }
        if model.dueActionCount > 0 { return "할일 \(model.dueActionCount)" }
        let day = DietStore(knowledgeRoot: model.knowledgeRoot).daySummary()
        if let line = day["summary_text"] as? String, !line.isEmpty {
            // Keep menu bar short
            if line.count > 22 { return String(line.prefix(20)) + "…" }
            return line.replacingOccurrences(of: "kcal", with: "k")
        }
        return "오늘"
    }
}
