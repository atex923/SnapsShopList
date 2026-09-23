import AVFoundation
import Photos
import SwiftUI
import UIKit

enum ProductPhotoStore {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProductPhotos", isDirectory: true)
    }

    static func save(_ image: UIImage) throws -> String {
        let data = try jpegData(for: image)
        return try save(data)
    }

    static func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileName = "\(UUID().uuidString).jpg"
        let url = folderURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func jpegData(for image: UIImage) throws -> Data {
        let optimizedImage = resizedForStorage(image)
        guard let data = optimizedImage.jpegData(compressionQuality: 0.82) else {
            throw PhotoError.encodingFailed
        }
        return data
    }

    private static func resizedForStorage(_ image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 1_600
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maximumDimension else { return image }

        let scale = maximumDimension / longestSide
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func load(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: folderURL.appendingPathComponent(fileName).path)
    }

    static func load(photo: ProductPhoto) -> UIImage? {
        if let imageData = photo.imageData, let image = UIImage(data: imageData) {
            return image
        }
        return load(fileName: photo.fileName)
    }

    static func delete(fileName: String) {
        let url = folderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppErrorLogger.record(
                error,
                category: "照片檔案",
                context: "刪除商品照片：\(fileName)"
            )
        }
    }

    static func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    AppErrorLogger.record(error, category: "相簿", context: "儲存商品照片")
                } else if !success {
                    AppErrorLogger.record(
                        message: "系統未完成照片儲存。",
                        category: "相簿",
                        context: "儲存商品照片"
                    )
                }
            }
        }
    }

    enum PhotoError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            "商品照片無法轉換成 JPEG。"
        }
    }
}

struct CameraPhotoPicker: View {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError = ""

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    CameraCaptureView(onImage: { image in
                        onImage(image)
                        dismiss()
                    }, onError: { message in
                        cameraError = message
                    })
                    .ignoresSafeArea()
                case .notDetermined:
                    ProgressView("正在要求相機權限…")
                        .task { await requestCameraAccess() }
                default:
                    ContentUnavailableView {
                        Label("無法使用相機", systemImage: "camera.fill")
                    } description: {
                        Text("請前往「設定」允許快拍購物帳本使用相機。")
                    } actions: {
                        Button("開啟設定") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .alert("相機無法使用", isPresented: Binding(
            get: { !cameraError.isEmpty },
            set: { if !$0 { cameraError = "" } }
        )) {
            Button("關閉", role: .cancel) { dismiss() }
        } message: {
            Text(cameraError)
        }
    }

    @MainActor
    private func requestCameraAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ProductCameraViewController {
        ProductCameraViewController(onImage: onImage, onError: onError)
    }

    func updateUIViewController(_ uiViewController: ProductCameraViewController, context: Context) {}
}

private final class ProductCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(
        label: "SnapshotBuyCheck.ProductCamera",
        qos: .userInitiated
    )
    private let onImage: (UIImage) -> Void
    private let onError: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentInput: AVCaptureDeviceInput?
    private var normalDevice: AVCaptureDevice?
    private var macroDevice: AVCaptureDevice?
    private var isConfigured = false
    private var isMacroEnabled = false

    private lazy var shutterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        button.accessibilityLabel = "拍照"
        return button
    }()

    private lazy var macroButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "camera.macro")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .black.withAlphaComponent(0.55)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(toggleMacroMode), for: .touchUpInside)
        button.accessibilityLabel = "近拍小花模式"
        return button
    }()

    init(onImage: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void) {
        self.onImage = onImage
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

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        view.addSubview(shutterButton)
        view.addSubview(macroButton)
        NSLayoutConstraint.activate([
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            macroButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            macroButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            macroButton.widthAnchor.constraint(equalToConstant: 50),
            macroButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        macroButton.isHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        shutterButton.layer.cornerRadius = shutterButton.bounds.width / 2
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configureSession() }
            guard self.isConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func configureSession() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        normalDevice = discovery.devices.first
        macroDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

        guard let device = normalDevice else {
            reportError("找不到可用的後置相機。")
            return
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        defer { captureSession.commitConfiguration() }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input), captureSession.canAddOutput(photoOutput) else {
                reportError("無法建立商品拍照工作階段。")
                return
            }
            captureSession.addInput(input)
            captureSession.addOutput(photoOutput)
            currentInput = input
            isConfigured = true
            DispatchQueue.main.async { [weak self] in
                self?.macroButton.isHidden = self?.macroDevice == nil
            }
        } catch {
            AppErrorLogger.record(error, category: "商品相機", context: "建立相機輸入")
            reportError("相機啟動失敗：\(error.localizedDescription)")
        }
    }

    @objc private func capturePhoto() {
        shutterButton.isEnabled = false
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            let settings = AVCapturePhotoSettings()
            if self.currentInput?.device.hasFlash == true,
               self.photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    @objc private func toggleMacroMode() {
        isMacroEnabled.toggle()
        let targetDevice = isMacroEnabled ? macroDevice : normalDevice
        macroButton.configuration?.baseBackgroundColor = isMacroEnabled
            ? UIColor.systemYellow.withAlphaComponent(0.82)
            : UIColor.black.withAlphaComponent(0.55)
        guard let targetDevice else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: targetDevice)
                self.captureSession.beginConfiguration()
                if let currentInput = self.currentInput {
                    self.captureSession.removeInput(currentInput)
                }
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.currentInput = newInput
                    if self.isMacroEnabled {
                        try targetDevice.lockForConfiguration()
                        if targetDevice.isAutoFocusRangeRestrictionSupported {
                            targetDevice.autoFocusRangeRestriction = .near
                        }
                        if targetDevice.isFocusModeSupported(.continuousAutoFocus) {
                            targetDevice.focusMode = .continuousAutoFocus
                        }
                        targetDevice.unlockForConfiguration()
                    }
                } else if let currentInput = self.currentInput,
                          self.captureSession.canAddInput(currentInput) {
                    self.captureSession.addInput(currentInput)
                }
                self.captureSession.commitConfiguration()
            } catch {
                AppErrorLogger.record(error, category: "商品相機", context: "切換近拍模式")
                self.reportError("無法切換近拍模式。")
            }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            AppErrorLogger.record(error, category: "商品相機", context: "擷取照片")
            reportError("拍照失敗：\(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.shutterButton.isEnabled = true }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            reportError("無法讀取剛拍攝的照片。")
            DispatchQueue.main.async { [weak self] in self?.shutterButton.isEnabled = true }
            return
        }
        DispatchQueue.main.async { [onImage] in onImage(image) }
    }

    private func reportError(_ message: String) {
        AppErrorLogger.record(message: message, category: "商品相機", context: "AVCaptureSession")
        DispatchQueue.main.async { [onError] in onError(message) }
    }
}
