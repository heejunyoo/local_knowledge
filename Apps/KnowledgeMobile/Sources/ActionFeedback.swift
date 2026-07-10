import Foundation
import SwiftUI

/// Global action feedback — every save/delete/connect result surfaces here.
@MainActor
final class ActionFeedback: ObservableObject {
    @Published var message: String?
    @Published var isError: Bool = false

    private var clearTask: Task<Void, Never>?

    func success(_ text: String) {
        show(text, error: false)
        kHapticSuccess()
    }

    func error(_ text: String) {
        show(text, error: true)
        kHapticLight()
    }

    func info(_ text: String) {
        show(text, error: false)
        kHapticLight()
    }

    private func show(_ text: String, error: Bool) {
        clearTask?.cancel()
        message = text
        isError = error
        let captured = text
        clearTask = Task {
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if message == captured {
                message = nil
            }
        }
    }

    func dismiss() {
        clearTask?.cancel()
        message = nil
    }
}

/// Top floating toast — single pattern for the whole mobile app.
struct KToastOverlay: View {
    @ObservedObject var feedback: ActionFeedback

    var body: some View {
        VStack {
            if let message = feedback.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: feedback.isError
                          ? "exclamationmark.circle.fill"
                          : "checkmark.circle.fill")
                        .foregroundStyle(feedback.isError ? KColor.red500 : KColor.green500)
                        .font(.system(size: 18))
                    Text(message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KColor.grey900)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        feedback.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(KColor.grey500)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal, KSpace.x6)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(KMotion.soft, value: feedback.message)
        .allowsHitTesting(feedback.message != nil)
    }
}
