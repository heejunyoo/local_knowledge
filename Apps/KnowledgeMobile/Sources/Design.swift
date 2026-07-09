import SwiftUI

/// Mobile design tokens — aligned with Mac TossTheme (docs/ui/toss_design.md).
enum KColor {
    static let blue500 = Color(red: 0.192, green: 0.510, blue: 0.965)
    static let blue50 = Color(red: 0.910, green: 0.953, blue: 1.0)
    static let grey900 = Color(red: 0.098, green: 0.122, blue: 0.157)
    static let grey700 = Color(red: 0.306, green: 0.349, blue: 0.408)
    static let grey500 = Color(red: 0.545, green: 0.584, blue: 0.631)
    static let grey200 = Color(red: 0.898, green: 0.910, blue: 0.922)
    static let grey100 = Color(red: 0.949, green: 0.957, blue: 0.965)
    static let red500 = Color(red: 0.941, green: 0.267, blue: 0.322)
    static let green500 = Color(red: 0.012, green: 0.698, blue: 0.424)
    static let white = Color.white
}

enum KSpace {
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

struct KPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? KColor.blue500 : KColor.grey200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(!enabled)
    }
}

struct KCard<Content: View>: View {
    var padded: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        Group {
            if padded {
                content().padding(KSpace.x5)
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct KListRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                            .lineLimit(1)
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
    }
}

struct KPageBackground: View {
    var body: some View {
        KColor.grey100.ignoresSafeArea()
    }
}
