import Photos
import SwiftUI
import UIKit

enum ProductPhotoStore {
    static var folderURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProductPhotos", isDirectory: true)
    }

    static func save(_ image: UIImage) throws -> String {
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let fileName = "\(UUID().uuidString).jpg"
        let url = folderURL.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw PhotoError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func load(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: folderURL.appendingPathComponent(fileName).path)
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(
            at: folderURL.appendingPathComponent(fileName)
        )
    }

    static func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
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
