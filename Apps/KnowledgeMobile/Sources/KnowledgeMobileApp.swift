import SwiftUI

@main
struct KnowledgeMobileApp: App {
    @StateObject private var core = CoreClient()
    @StateObject private var feedback = ActionFeedback()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(core)
                .environmentObject(feedback)
                .tint(KColor.blue500)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var core: CoreClient
    @EnvironmentObject var feedback: ActionFeedback

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if core.isPaired {
                    MainTabs()
                } else {
                    PairingView()
                }
            }
            KToastOverlay(feedback: feedback)
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
