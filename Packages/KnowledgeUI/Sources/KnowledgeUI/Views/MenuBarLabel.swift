import SwiftUI

public struct MenuBarLabel: View {
    public var isRecording: Bool
    public var badge: Int
    /// Short status for menu bar (W2 C6-F3).
    public var statusLine: String

    public init(isRecording: Bool, badge: Int, statusLine: String = "") {
        self.isRecording = isRecording
        self.badge = badge
        self.statusLine = statusLine
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRecording ? "waveform.circle.fill" : "brain.head.profile")
            if isRecording {
                Text("REC")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            } else if !statusLine.isEmpty {
                Text(statusLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
    }
}
