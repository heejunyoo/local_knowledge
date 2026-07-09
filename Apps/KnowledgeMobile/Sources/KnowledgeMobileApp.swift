import SwiftUI

@main
struct KnowledgeMobileApp: App {
    @StateObject private var core = CoreClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(core)
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

struct MainTabs: View {
    @EnvironmentObject var core: CoreClient

    var body: some View {
        TabView {
            HomeMobileView()
                .tabItem { Label("홈", systemImage: "house.fill") }
            DietMobileView()
                .tabItem { Label("식단", systemImage: "fork.knife.circle.fill") }
            AskMobileView()
                .tabItem { Label("물어보기", systemImage: "bubble.left.and.bubble.right.fill") }
            SearchMobileView()
                .tabItem { Label("검색", systemImage: "magnifyingglass") }
            ReviewMobileView()
                .tabItem {
                    Label("확인함", systemImage: "tray.full.fill")
                }
                .badge(core.reviewCount > 0 ? core.reviewCount : 0)
            SettingsMobileView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        .tint(Color(red: 0.19, green: 0.51, blue: 0.96))
    }
}
