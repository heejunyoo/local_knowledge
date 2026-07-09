import SwiftUI
import AppKit
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
        // Ensure a window is key (SPM naked binary / first launch).
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            if NSApp.windows.isEmpty {
                // Fallback: open first WindowGroup via openUntitledDocument if needed
            }
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
            HomeView(model: model)
                .frame(minWidth: 400, idealWidth: 420, minHeight: 560, idealHeight: 620)
        }
        .defaultSize(width: 420, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            HomeView(model: model)
                .frame(width: 400, height: 560)
        } label: {
            MenuBarLabel(
                isRecording: model.isRecording,
                badge: model.reviewCount + model.failedCount
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
                    Text(model.healthOK ? "데몬 연결됨 · \(model.daemonVersion)" : "데몬이 꺼져 있어요")
                        .font(TossFont.body())
                        .foregroundStyle(model.healthOK ? TossColor.grey700 : TossColor.red500)
                    Text("토스 철학: 단순한 한 가지 일, 넉넉한 여백, 조용한 성공.")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey700)
                    Spacer()
                }
                .padding(TossSpace.x6)
            }
            .frame(width: 360, height: 260)
        }
    }
}
