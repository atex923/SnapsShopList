import Foundation
import ImageIO
@preconcurrency import Vision

enum OverseasTextRecognitionError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: "無法讀取拍攝的圖片。"
        case .noText: "照片中沒有辨識到可用文字，請靠近文字後重試。"
        }
    }
}

enum OverseasTextRecognizer {
    static func recognize(_ data: Data) async throws -> [String] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OverseasTextRecognitionError.invalidImage
        }

        let candidates: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let rawLines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                var seen = Set<String>()
                continuation.resume(returning: rawLines.filter { !$0.isEmpty && seen.insert($0).inserted })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hant", "en-US", "ja-JP", "ko-KR"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard !candidates.isEmpty else { throw OverseasTextRecognitionError.noText }
        return candidates
    }
}
