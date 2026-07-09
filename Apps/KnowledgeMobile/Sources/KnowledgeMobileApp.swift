import SwiftUI

@main
struct KnowledgeMobileApp: App {
    @StateObject private var core = CoreClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(core)
                .tint(KColor.blue500)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var core: CoreClient

    var body: some View {
        Group {
            if core.isPaired {
                MainTabs()
            } else {
                PairingView()
            }
        }
        .task { await core.refreshStatus() }
    }
}

/// 홈 · 물어보기 · 식단 · 더보기
struct MainTabs: View {
    @EnvironmentObject var core: CoreClient

    var body: some View {
        TabView {
            HomeMobileView()
                .tabItem { Label("홈", systemImage: "house.fill") }
            AskMobileView()
                .tabItem { Label("물어보기", systemImage: "bubble.left.and.bubble.right.fill") }
            DietMobileView()
                .tabItem { Label("식단", systemImage: "fork.knife.circle.fill") }
            MoreMobileView()
                .tabItem { Label("더보기", systemImage: "ellipsis.circle.fill") }
                .badge(core.reviewCount > 0 ? core.reviewCount : 0)
        }
    }
}
