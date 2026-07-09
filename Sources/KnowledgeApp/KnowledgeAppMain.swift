import SwiftUI
import KnowledgeUI
import KnowledgeCore

@main
struct KnowledgeAppMain: App {
    @StateObject private var model = AppModel(
        knowledgeRoot: KnowledgePaths.defaultKnowledgeRoot
    )

    var body: some Scene {
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
                    Text("토스 철학: 단순한 한 가지 일, 넉넉한 여백, 조용한 성공.")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey700)
                    Spacer()
                }
                .padding(TossSpace.x6)
            }
            .frame(width: 360, height: 240)
        }
    }
}
