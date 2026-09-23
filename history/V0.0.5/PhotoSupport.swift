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

struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPhotoPicker

        init(parent: CameraPhotoPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
