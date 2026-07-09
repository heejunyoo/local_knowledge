import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Toss-inspired tokens (not official TDS). Adaptive light/dark for macOS.
public enum TossColor {
    public static let blue500 = Color(hex: 0x3182F6)
    public static let green500 = Color(hex: 0x03B26C)
    public static let red500 = Color(hex: 0xF04452)
    public static let white = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)

    public static let blue50 = adaptive(light: 0xE8F3FF, dark: 0x1A2740)
    public static let red50 = adaptive(light: 0xFFEEEE, dark: 0x3A1F1F)
    public static let grey900 = adaptive(light: 0x191F28, dark: 0xF2F4F6)
    public static let grey700 = adaptive(light: 0x4E5968, dark: 0xC4C8CE)
    public static let grey500 = adaptive(light: 0x8B95A1, dark: 0x8E959E)
    public static let grey200 = adaptive(light: 0xE5E8EB, dark: 0x3A3A3C)
    public static let grey100 = adaptive(light: 0xF2F4F6, dark: 0x1C1C1E)
    public static let grey50 = adaptive(light: 0xF9FAFB, dark: 0x000000)

    /// On primary blue buttons — always white for contrast.
    public static let onPrimary = Color.white

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsHex(isDark ? dark : light)
        }))
        #else
        return Color(hex: light)
        #endif
    }

    #if canImport(AppKit)
    private static func nsHex(_ hex: UInt32) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    #endif
}

public enum TossSpace {
    public static let x1: CGFloat = 4
    public static let x2: CGFloat = 8
    public static let x3: CGFloat = 12
    public static let x4: CGFloat = 16
    public static let x5: CGFloat = 20
    public static let x6: CGFloat = 24
    public static let x8: CGFloat = 32
}

public enum TossRadius {
    public static let button: CGFloat = 12
    public static let card: CGFloat = 16
    public static let badge: CGFloat = 8
}

public enum TossFont {
    public static func title() -> Font { .system(size: 28, weight: .semibold) }
    public static func section() -> Font { .system(size: 17, weight: .semibold) }
    public static func body() -> Font { .system(size: 15, weight: .regular) }
    public static func caption() -> Font { .system(size: 13, weight: .regular) }
    public static func button() -> Font { .system(size: 16, weight: .semibold) }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Motion

public enum TossMotion {
    public static let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)
}

public struct TossAppear: ViewModifier {
    @State private var shown = false
    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(TossMotion.soft) { shown = true }
            }
    }
}

public extension View {
    func tossAppear() -> some View { modifier(TossAppear()) }
}

// MARK: - Components

public struct TossPrimaryButton: View {
    public var title: String
    public var enabled: Bool
    public var action: () -> Void

    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(TossFont.button())
                .foregroundStyle(TossColor.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? TossColor.blue500 : TossColor.grey200)
                .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

public struct TossSecondaryButton: View {
    public var title: String
    public var action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(TossFont.button())
                .foregroundStyle(TossColor.grey900)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(TossColor.grey100)
                .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

public struct TossCard<Content: View>: View {
    public var content: () -> Content
    public var padded: Bool

    public init(padded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.padded = padded
        self.content = content
    }

    public var body: some View {
        Group {
            if padded {
                content().padding(TossSpace.x5)
            } else {
                content().padding(.horizontal, TossSpace.x5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

public struct TossListRow: View {
    public var title: String
    public var subtitle: String?
    public var systemImage: String
    public var trailing: String?
    public var action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TossSpace.x3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TossColor.blue50)
                        .frame(width: 40, height: 40)
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.blue500)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TossFont.body())
                        .fontWeight(.medium)
                        .foregroundStyle(TossColor.grey900)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey500)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: TossSpace.x2)
                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(TossFont.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(TossColor.blue500)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TossColor.grey200)
            }
            .padding(.vertical, TossSpace.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + (subtitle.map { ", \($0)" } ?? ""))
    }
}

public struct TossBadge: View {
    public enum Kind { case info, danger, neutral }
    public var text: String
    public var kind: Kind

    public init(_ text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(TossFont.caption())
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, TossSpace.x2)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: TossRadius.badge, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .info: return TossColor.blue500
        case .danger: return TossColor.red500
        case .neutral: return TossColor.grey700
        }
    }

    private var background: Color {
        switch kind {
        case .info: return TossColor.blue50
        case .danger: return TossColor.red50
        case .neutral: return TossColor.grey100
        }
    }
}

public struct TossScreenHeader: View {
    public var title: String
    public var subtitle: String?
    public var onHome: (() -> Void)?

    public init(title: String, subtitle: String? = nil, onHome: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.onHome = onHome
    }

    public var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text(title)
                    .font(TossFont.title())
                    .foregroundStyle(TossColor.grey900)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: TossSpace.x3)
            if let onHome {
                Button("홈", action: onHome)
                    .font(TossFont.body())
                    .fontWeight(.semibold)
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
                    .padding(.top, 6)
            }
        }
    }
}

/// Quiet empty / zero state — one icon, one line, optional action.
public struct TossEmptyState: View {
    public var systemImage: String
    public var title: String
    public var message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: TossSpace.x4) {
            ZStack {
                Circle()
                    .fill(TossColor.blue50)
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
            }
            Text(title)
                .font(TossFont.section())
                .foregroundStyle(TossColor.grey900)
                .multilineTextAlignment(.center)
            Text(message)
                .font(TossFont.body())
                .foregroundStyle(TossColor.grey500)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TossFont.body())
                    .fontWeight(.semibold)
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
                    .padding(.top, TossSpace.x2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(TossSpace.x6)
        .tossAppear()
    }
}

public enum StatusCopy {
    public static func label(_ raw: String) -> String {
        switch raw {
        case "recording": return "녹음 중"
        case "recorded": return "녹음 완료"
        case "transcribing": return "받아쓰는 중"
        case "transcribed": return "받아쓰기 완료"
        case "summarizing": return "요약하는 중"
        case "summarized_candidate": return "요약 준비됨"
        case "review_needed": return "확인 필요"
        case "commit_pending": return "저장 중"
        case "committed": return "저장됨"
        case "record_failed": return "녹음 실패"
        case "transcribe_failed": return "받아쓰기 실패"
        case "summary_failed": return "요약 실패"
        case "commit_failed": return "저장 실패"
        case "abandoned": return "중단됨"
        default: return raw
        }
    }

    public static func badgeKind(_ raw: String) -> TossBadge.Kind {
        if raw.contains("fail") { return .danger }
        if raw == "review_needed" || raw == "recording" { return .info }
        return .neutral
    }
}
