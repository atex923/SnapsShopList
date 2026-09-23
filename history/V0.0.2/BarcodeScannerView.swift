import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    let onCode: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    ZStack {
                        BarcodeScannerView(onCode: onCode)
                            .ignoresSafeArea()

                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                            .frame(width: 300, height: 190)
                            .shadow(color: .black.opacity(0.5), radius: 5)

                        VStack {
                            Spacer()
                            Text("將食品條碼置於框線內")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.62), in: Capsule())
                                .padding(.bottom, 48)
                        }
                    }

                case .notDetermined:
                    ProgressView("正在要求相機權限…")
                        .task { await requestCameraAccess() }

                default:
                    ContentUnavailableView {
                        Label("無法使用相機", systemImage: "camera.fill")
                    } description: {
                        Text("請前往「設定」允許採買記事工使用相機。")
                    } actions: {
                        Button("開啟設定") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("掃描食品條碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func requestCameraAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

private final class BarcodeScannerViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate {

    private let captureSession = AVCaptureSession()
    private let metadataQueue = DispatchQueue(label: "SnapshotBuyCheck.BarcodeMetadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onCode: (String) -> Void
    private var hasReturnedCode = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 尚未實作")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasReturnedCode = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        defer { captureSession.commitConfiguration() }

        guard
            let camera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera),
            captureSession.canAddInput(input)
        else { return }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)

        let desiredTypes: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code39, .code93, .code128, .qr
        ]
        output.metadataObjectTypes = desiredTypes.filter {
            output.availableMetadataObjectTypes.contains($0)
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            !hasReturnedCode,
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue,
            !value.isEmpty
        else { return }

        hasReturnedCode = true
        captureSession.stopRunning()
        DispatchQueue.main.async { [onCode] in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode(value)
        }
    }
}
