import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Render a QR code NSImage for pairing / share.
public enum QRCodeImage {
    public static func nsImage(from string: String, dimension: CGFloat = 200) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    public static func swiftUIImage(from string: String, dimension: CGFloat = 180) -> Image? {
        guard let ns = nsImage(from: string, dimension: dimension) else { return nil }
        return Image(nsImage: ns)
    }
}

public struct TossQRCodeView: View {
    public var payload: String
    public var dimension: CGFloat

    public init(payload: String, dimension: CGFloat = 180) {
        self.payload = payload
        self.dimension = dimension
    }

    public var body: some View {
        Group {
            if let img = QRCodeImage.swiftUIImage(from: payload, dimension: dimension) {
                img
                    .interpolation(.none)
                    .resizable()
                    .frame(width: dimension, height: dimension)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("QR을 만들지 못했어요")
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.grey500)
            }
        }
        .accessibilityLabel("페어링 QR 코드")
    }
}
