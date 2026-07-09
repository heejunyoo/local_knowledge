import SwiftUI
import AVFoundation

/// Camera QR scanner for Knowledge pairing payload.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        vc.onClose = onClose
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onClose: (() -> Void)?
        private let session = AVCaptureSession()
        private var didEmit = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let close = UIButton(type: .system)
            close.setTitle("닫기", for: .normal)
            close.setTitleColor(.white, for: .normal)
            close.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)

            let hint = UILabel()
            hint.text = "Mac 설정의 QR을 비춰 주세요"
            hint.textColor = .white
            hint.font = .systemFont(ofSize: 15, weight: .medium)
            hint.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hint)

            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ])

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.insertSublayer(preview, at: 0)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.first { $0 is AVCaptureVideoPreviewLayer }?.frame = view.bounds
        }

        @objc private func closeTapped() {
            session.stopRunning()
            onClose?()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didEmit,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let value = obj.stringValue else { return }
            didEmit = true
            session.stopRunning()
            onCode?(value)
        }
    }
}
