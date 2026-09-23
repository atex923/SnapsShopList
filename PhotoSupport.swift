import AVFoundation
import AVKit
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoSourceMenu<Content: View>: View {
    let maximumSelectionCount: Int
    let onCamera: () -> Void
    let onPhotoData: (Data) -> Void
    let onError: (String) -> Void
    private let label: () -> Content

    init(
        maximumSelectionCount: Int,
        onCamera: @escaping () -> Void,
        onPhotoData: @escaping (Data) -> Void,
        onError: @escaping (String) -> Void,
        @ViewBuilder label: @escaping () -> Content
    ) {
        self.maximumSelectionCount = maximumSelectionCount
        self.onCamera = onCamera
        self.onPhotoData = onPhotoData
        self.onError = onError
        self.label = label
    }

    var body: some View {
        Button(action: onCamera) {
            label()
        }
        .accessibilityHint("直接開啟相機；可在相機畫面改從相簿選取")
    }
}

enum ProductPhotoStore {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProductPhotos", isDirectory: true)
    }

    // Legacy file support only. New photos are stored once in SwiftData external storage.
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

    static func optimizedJPEG(from sourceData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
                throw PhotoError.encodingFailed
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw PhotoError.encodingFailed
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { throw PhotoError.encodingFailed }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.82
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PhotoError.encodingFailed }
            return output as Data
        }.value
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
        guard !fileName.isEmpty else { return }
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

    static func saveToPhotoLibrary(
        _ data: Data,
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(PhotoError.photoLibraryPermissionDenied))
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    AppErrorLogger.record(error, category: "相簿", context: "儲存商品照片")
                    DispatchQueue.main.async { completion(.failure(error)) }
                } else if !success {
                    AppErrorLogger.record(
                        message: "系統未完成照片儲存。",
                        category: "相簿",
                        context: "儲存商品照片"
                    )
                    DispatchQueue.main.async { completion(.failure(PhotoError.photoLibrarySaveFailed)) }
                } else {
                    DispatchQueue.main.async { completion(.success(())) }
                }
            }
        }
    }

    enum PhotoError: LocalizedError {
        case encodingFailed
        case photoLibraryPermissionDenied
        case photoLibrarySaveFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "商品照片無法轉換成 JPEG。"
            case .photoLibraryPermissionDenied: "沒有相簿新增權限；照片已保留在目前表單，請到設定允許後再拍一次。"
            case .photoLibrarySaveFailed: "照片已保留在 App，但系統相簿未完成儲存。"
            }
        }
    }
}

enum CameraPhotoSource: Equatable {
    case camera
    case photoLibrary
}

struct CameraPhotoPicker: View {
    let onPhotoData: (Data, CameraPhotoSource) -> Void
    let onCancel: () -> Void
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError = ""
    @State private var selectedLibraryItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    CameraCaptureView(onPhotoData: { data in
                        onPhotoData(data, .camera)
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
                        Text("請前往「設定」允許購物記本使用相機。")
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
                    Button("關閉", systemImage: "xmark") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedLibraryItem, matching: .images) {
                        Label("選取照片", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityHint("從相簿選取商品照片")
                }
            }
        }
        .onChange(of: selectedLibraryItem) { _, item in
            guard let item else { return }
            Task { await importLibraryPhoto(item) }
        }
        .alert("相機無法使用", isPresented: Binding(
            get: { !cameraError.isEmpty },
            set: { if !$0 { cameraError = "" } }
        )) {
            Button("關閉", role: .cancel) { onCancel() }
        } message: {
            Text(cameraError)
        }
    }

    @MainActor
    private func requestCameraAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    @MainActor
    private func importLibraryPhoto(_ item: PhotosPickerItem) async {
        defer { selectedLibraryItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                cameraError = "無法讀取選取的照片。"
                return
            }
            onPhotoData(data, .photoLibrary)
        } catch {
            AppErrorLogger.record(error, category: "相簿讀取", context: "商品相機內選取照片")
            cameraError = error.localizedDescription
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onPhotoData: (Data) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ProductCameraViewController {
        ProductCameraViewController(onPhotoData: onPhotoData, onError: onError)
    }

    func updateUIViewController(_ uiViewController: ProductCameraViewController, context: Context) {}
}

private final class ProductCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private var captureSession: AVCaptureSession?
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(
        label: "SnapsShopList.ProductCamera",
        qos: .userInitiated
    )
    private let onPhotoData: (Data) -> Void
    private let onError: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentInput: AVCaptureDeviceInput?
    private var normalDevice: AVCaptureDevice?
    private var macroDevice: AVCaptureDevice?
    private var isConfigured = false
    private var isMacroEnabled = false
    private var isCapturingPhoto = false
    private var captureEventInteraction: AVCaptureEventInteraction?

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

    init(onPhotoData: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
        self.onPhotoData = onPhotoData
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
        configureHardwareCaptureButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        shutterButton.layer.cornerRadius = shutterButton.bounds.width / 2
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureEventInteraction?.isEnabled = true
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
            if !self.isConfigured { self.configureSession() }
            if let activeDevice = self.currentInput?.device {
                self.setOneTimesZoom(on: activeDevice)
            }
            guard let captureSession = self.captureSession,
                  self.isConfigured, !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureEventInteraction?.isEnabled = false
        sessionQueue.async { [weak self] in
            guard let self, let captureSession = self.captureSession,
                  captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func configureSession() {
        guard let captureSession else { return }
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
            setOneTimesZoom(on: device)
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
        sessionQueue.async { [weak self] in
            guard let self,
                  self.isConfigured,
                  self.captureSession?.isRunning == true,
                  !self.isCapturingPhoto else { return }
            self.isCapturingPhoto = true
            DispatchQueue.main.async { [weak self] in self?.shutterButton.isEnabled = false }
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
            guard let self, let captureSession = self.captureSession else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: targetDevice)
                captureSession.beginConfiguration()
                if let currentInput = self.currentInput {
                    captureSession.removeInput(currentInput)
                }
                if captureSession.canAddInput(newInput) {
                    captureSession.addInput(newInput)
                    self.currentInput = newInput
                    self.setOneTimesZoom(on: targetDevice)
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
                          captureSession.canAddInput(currentInput) {
                    captureSession.addInput(currentInput)
                }
                captureSession.commitConfiguration()
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
            finishCapture()
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            reportError("無法讀取剛拍攝的照片。")
            finishCapture()
            return
        }
        finishCapture()
        DispatchQueue.main.async { [onPhotoData] in onPhotoData(data) }
    }

    private func finishCapture() {
        sessionQueue.async { [weak self] in
            self?.isCapturingPhoto = false
            DispatchQueue.main.async { [weak self] in self?.shutterButton.isEnabled = true }
        }
    }

    private func configureHardwareCaptureButton() {
        guard #available(iOS 17.2, *) else { return }
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.capturePhoto()
        }
        view.addInteraction(interaction)
        captureEventInteraction = interaction
    }

    private func setOneTimesZoom(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let zoom = min(max(CGFloat(1), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {
            AppErrorLogger.record(error, category: "商品相機", context: "設定 1.0 倍倍率")
        }
    }

    private func reportError(_ message: String) {
        AppErrorLogger.record(message: message, category: "商品相機", context: "AVCaptureSession")
        DispatchQueue.main.async { [onError] in onError(message) }
    }
}
