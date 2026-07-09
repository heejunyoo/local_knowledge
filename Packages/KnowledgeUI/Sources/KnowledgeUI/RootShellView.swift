import SwiftUI

/// Top-level IA (Toss): 홈 · 물어보기 · 식단 · 더보기 — one job per surface.
public struct RootShellView: View {
    @ObservedObject public var model: AppModel
    @State private var tab: ShellTab = .home

    public enum ShellTab: Hashable {
        case home
        case chat
        case diet
        case more
    }

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $tab) {
            HomeView(model: model)
                .tabItem { Label("홈", systemImage: "house.fill") }
                .tag(ShellTab.home)

            ChatView(model: model, showsBackButton: false)
                .tabItem { Label("물어보기", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(ShellTab.chat)

            DietView(knowledgeRoot: model.knowledgeRoot)
                .tabItem { Label("식단", systemImage: "fork.knife.circle.fill") }
                .tag(ShellTab.diet)

            MoreHubView(model: model)
                .tabItem { Label("더보기", systemImage: "ellipsis.circle.fill") }
                .tag(ShellTab.more)
                .badge(model.reviewCount > 0 ? model.reviewCount : 0)
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 640, idealHeight: 740)
    }
}
