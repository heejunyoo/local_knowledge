import SwiftUI

/// Top-level shell: 홈 | 식단 tabs (other features remain on Home hub).
public struct RootShellView: View {
    @ObservedObject public var model: AppModel
    @State private var tab: ShellTab = .home

    public enum ShellTab: Hashable {
        case home
        case diet
    }

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $tab) {
            HomeView(model: model)
                .tabItem { Label("홈", systemImage: "house.fill") }
                .tag(ShellTab.home)

            DietView(knowledgeRoot: model.knowledgeRoot)
                .tabItem { Label("식단", systemImage: "fork.knife.circle.fill") }
                .tag(ShellTab.diet)
        }
        // macOS TabView styling
        .frame(minWidth: 420, idealWidth: 480, minHeight: 620, idealHeight: 720)
    }
}
