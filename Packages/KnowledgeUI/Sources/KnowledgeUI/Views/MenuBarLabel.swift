import SwiftUI

public struct MenuBarLabel: View {
    public var isRecording: Bool
    public var badge: Int

    public init(isRecording: Bool, badge: Int) {
        self.isRecording = isRecording
        self.badge = badge
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRecording ? "waveform.circle.fill" : "brain.head.profile")
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
    }
}
