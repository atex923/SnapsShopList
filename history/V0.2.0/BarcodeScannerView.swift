import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isManualEntryPresented = false
    @State private var manualBarcode = ""
    @State private var scannerError = ""
    let onCode: (String) -> Void
    let onNoBarcode: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    ZStack {
                        BarcodeScannerView(onCode: onCode) { message in
                            scannerError = message
                        }
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
                        Text("請前往「設定」允許購物記本使用相機。")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("手動輸入", systemImage: "keyboard") {
                        isManualEntryPresented = true
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("建立無條碼商品", systemImage: "tag.slash.fill") {
                    onNoBarcode()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .alert("手動輸入條碼", isPresented: $isManualEntryPresented) {
            TextField("商品條碼", text: $manualBarcode)
                .keyboardType(.asciiCapableNumberPad)
            Button("取消", role: .cancel) {}
            Button("確定") {
                let code = manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { return }
                onCode(code)
            }
        } message: {
            Text("條碼無法辨識時，可直接輸入包裝上的數字。")
        }
        .alert("無法啟動掃描", isPresented: Binding(
            get: { !scannerError.isEmpty },
            set: { if !$0 { scannerError = "" } }
        )) {
            Button("改用手動輸入") { isManualEntryPresented = true }
            Button("關閉", role: .cancel) { dismiss() }
        } message: {
            Text(scannerError)
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
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(onCode: onCode, onError: onError)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

private final class BarcodeScannerViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate {

    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(
        label: "SnapsShopList.CaptureSession",
        qos: .userInitiated
    )
    private let metadataQueue = DispatchQueue(label: "SnapsShopList.BarcodeMetadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onCode: (String) -> Void
    private let onError: (String) -> Void
    private var hasReturnedCode = false
    private var isConfigured = false

    init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onCode = onCode
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 尚未實作")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        metadataQueue.async { [weak self] in
            self?.hasReturnedCode = false
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession == nil {
                let session = AVCaptureSession()
                self.captureSession = session
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let layer = AVCaptureVideoPreviewLayer(session: session)
                    layer.videoGravity = .resizeAspectFill
                    layer.frame = self.view.bounds
                    self.view.layer.insertSublayer(layer, at: 0)
                    self.previewLayer = layer
                }
            }
            if !isConfigured {
                configureCaptureSession()
            }
            guard let captureSession, isConfigured, !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, let captureSession, captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func configureCaptureSession() {
        guard let captureSession else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        defer { captureSession.commitConfiguration() }

        guard
            let camera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera),
            captureSession.canAddInput(input)
        else {
            reportError("找不到可用的相機輸入，請改用手動輸入條碼。")
            return
        }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            reportError("無法建立條碼辨識輸出，請改用手動輸入條碼。")
            return
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)

        let desiredTypes: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code39, .code93, .code128, .qr
        ]
        output.metadataObjectTypes = desiredTypes.filter {
            output.availableMetadataObjectTypes.contains($0)
        }
        guard !output.metadataObjectTypes.isEmpty else {
            reportError("這台裝置不支援目前的條碼格式。")
            return
        }
        isConfigured = true
    }

    private func reportError(_ message: String) {
        AppErrorLogger.record(message: message, category: "條碼掃描", context: "AVCaptureSession")
        DispatchQueue.main.async { [onError] in
            onError(message)
        }
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
        sessionQueue.async { [weak self] in
            guard let self, let captureSession, captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
        DispatchQueue.main.async { [onCode] in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode(value)
        }
    }
}
