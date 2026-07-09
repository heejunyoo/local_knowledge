import SwiftUI

/// Toss-inspired tokens for Knowledge (not official TDS assets).
public enum TossColor {
    public static let blue500 = Color(hex: 0x3182F6)
    public static let blue50 = Color(hex: 0xE8F3FF)
    public static let grey900 = Color(hex: 0x191F28)
    public static let grey700 = Color(hex: 0x4E5968)
    public static let grey500 = Color(hex: 0x8B95A1)
    public static let grey200 = Color(hex: 0xE5E8EB)
    public static let grey100 = Color(hex: 0xF2F4F6)
    public static let grey50 = Color(hex: 0xF9FAFB)
    public static let red500 = Color(hex: 0xF04452)
    public static let red50 = Color(hex: 0xFFEEEE)
    public static let green500 = Color(hex: 0x03B26C)
    public static let white = Color.white
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
                .foregroundStyle(TossColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? TossColor.blue500 : TossColor.grey200)
                .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
    }
}

public struct TossCard<Content: View>: View {
    public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous)
                    .stroke(TossColor.grey200, lineWidth: 1)
            )
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
