import SwiftUI

/// Secondary destinations — not competing with primary tabs.
public struct MoreHubView: View {
    @ObservedObject public var model: AppModel
    @State private var path = NavigationPath()

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                TossColor.grey100.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TossSpace.x6) {
                        Text("더보기")
                            .font(TossFont.title())
                            .foregroundStyle(TossColor.grey900)
                            .padding(.top, TossSpace.x6)

                        Text("확인·검색·연결·설정")
                            .font(TossFont.body())
                            .foregroundStyle(TossColor.grey500)

                        TossCard(padded: false) {
                            VStack(spacing: 0) {
                                TossListRow(
                                    title: "확인함",
                                    subtitle: model.reviewCount > 0 ? "저장 전 \(model.reviewCount)건" : "비어 있어요",
                                    systemImage: "checkmark.circle.fill",
                                    trailing: model.reviewCount > 0 ? "\(model.reviewCount)" : nil
                                ) { path.append(AppRoute.review) }
                                divider
                                TossListRow(
                                    title: "찾아보기",
                                    subtitle: "키워드로 검색",
                                    systemImage: "magnifyingglass"
                                ) { path.append(AppRoute.search) }
                                divider
                                TossListRow(
                                    title: "지식 연결",
                                    subtitle: model.corpusTotalUnits > 0 ? "\(model.corpusTotalUnits)개 단위" : "메모·폴더 가져오기",
                                    systemImage: "folder.fill",
                                    trailing: model.corpusTotalUnits > 0 ? "\(model.corpusTotalUnits)" : nil
                                ) { path.append(AppRoute.library) }
                                divider
                                TossListRow(
                                    title: "설정",
                                    subtitle: "보관 · AI · 모바일 연결",
                                    systemImage: "gearshape.fill"
                                ) { path.append(AppRoute.settings) }
                            }
                            .padding(.vertical, TossSpace.x2)
                        }

                        Spacer(minLength: TossSpace.x8)
                    }
                    .padding(.horizontal, TossSpace.x6)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
                    .navigationBarBackButtonHidden(true)
            }
        }
    }

    private var divider: some View {
        Divider().overlay(TossColor.grey200).padding(.leading, 56)
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .review: ReviewInboxView(model: model)
        case .search: SearchView(model: model)
        case .library: SourcesView(model: model)
        case .settings: SettingsView(model: model)
        case .record: RecordView(model: model)
        case .chat: ChatView(model: model)
        case .diet: DietView(knowledgeRoot: model.knowledgeRoot)
        }
    }
}
