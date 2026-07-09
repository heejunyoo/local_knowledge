import SwiftUI
import UIKit

/// Mobile design tokens — aligned with Mac TossTheme (docs/ui/toss_design.md). Adaptive dark mode.
enum KColor {
    static let blue500 = Color(uiColor: UIColor { t in
        UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)
    })
    static let green500 = Color(uiColor: UIColor { _ in UIColor(red: 0.012, green: 0.698, blue: 0.424, alpha: 1) })
    static let red500 = Color(uiColor: UIColor { _ in UIColor(red: 0.941, green: 0.267, blue: 0.322, alpha: 1) })
    static let onPrimary = Color.white

    static let blue50 = adaptive(
        light: UIColor(red: 0.910, green: 0.953, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.15, blue: 0.25, alpha: 1)
    )
    static let grey900 = adaptive(
        light: UIColor(red: 0.098, green: 0.122, blue: 0.157, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
    )
    static let grey700 = adaptive(
        light: UIColor(red: 0.306, green: 0.349, blue: 0.408, alpha: 1),
        dark: UIColor(red: 0.77, green: 0.78, blue: 0.81, alpha: 1)
    )
    static let grey500 = adaptive(
        light: UIColor(red: 0.545, green: 0.584, blue: 0.631, alpha: 1),
        dark: UIColor(red: 0.56, green: 0.58, blue: 0.62, alpha: 1)
    )
    static let grey200 = adaptive(
        light: UIColor(red: 0.898, green: 0.910, blue: 0.922, alpha: 1),
        dark: UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1)
    )
    static let grey100 = adaptive(
        light: UIColor(red: 0.949, green: 0.957, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let white = adaptive(
        light: .white,
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum KSpace {
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

enum KMotion {
    static let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

func kHapticLight() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

func kHapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

struct KPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            if enabled { kHapticLight() }
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KColor.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? KColor.blue500 : KColor.grey200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

struct KCard<Content: View>: View {
    var padded: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        Group {
            if padded { content().padding(KSpace.x5) } else { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }
}

struct KListRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            kHapticLight()
            action()
        } label: {
            HStack(spacing: KSpace.x3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KColor.blue50)
                        .frame(width: 40, height: 40)
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KColor.blue500)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KColor.grey900)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(KColor.grey500)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KColor.blue500)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KColor.grey200)
            }
            .padding(.vertical, KSpace.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct KEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var shown = false

    var body: some View {
        VStack(spacing: KSpace.x4) {
            ZStack {
                Circle().fill(KColor.blue50).frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(KColor.blue500)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KColor.grey900)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(KColor.grey500)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle) {
                    kHapticLight()
                    action()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KColor.blue500)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(KSpace.x6)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 8)
        .onAppear {
            withAnimation(KMotion.soft) { shown = true }
        }
    }
}

struct KPageBackground: View {
    var body: some View {
        KColor.grey100.ignoresSafeArea()
    }
}
