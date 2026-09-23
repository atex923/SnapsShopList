import SwiftUI
import UIKit

enum OverseasModeSettings {
    static let enabledKey = "SnapsShopList.overseasModeEnabled"
    static let currencyKey = "SnapsShopList.defaultCurrencyCode"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var activeCurrencyCode: String {
        PurchaseCurrencyPolicy.activeCode(
            overseasModeEnabled: isEnabled,
            preferredCode: UserDefaults.standard.string(forKey: currencyKey) ?? SupportedCurrency.TWD.rawValue
        )
    }
}

struct OverseasTextCaptureButton: View {
    let title: String
    let onSelect: (String) -> Void

    @State private var isCameraPresented = false
    @State private var isResultPresented = false
    @State private var isRecognizing = false
    @State private var candidates: [String] = []
    @State private var errorMessage = ""

    var body: some View {
        Button {
            isCameraPresented = true
        } label: {
            Label(title, systemImage: "text.viewfinder")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isRecognizing)
        .overlay(alignment: .trailing) {
            if isRecognizing { ProgressView() }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data in
                isCameraPresented = false
                recognizeAfterCameraDismisses(data)
            }, onCancel: {
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isResultPresented) {
            NavigationStack {
                List {
                    Section("選擇辨識文字") {
                        ForEach(candidates, id: \.self) { candidate in
                            Button(candidate) {
                                onSelect(candidate)
                                isResultPresented = false
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    Section {
                        Button("使用全部文字") {
                            onSelect(candidates.joined(separator: " "))
                            isResultPresented = false
                        }
                    }
                }
                .navigationTitle("文字辨識結果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isResultPresented = false }
                    }
                }
            }
        }
        .alert("文字辨識", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func recognizeAfterCameraDismisses(_ data: Data) {
        isRecognizing = true
        Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                candidates = try await OverseasTextRecognizer.recognize(data)
                isRecognizing = false
                isResultPresented = true
            } catch {
                isRecognizing = false
                AppErrorLogger.record(error, category: "海外 OCR", context: title)
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ForeignNameLookupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let barcode: String
    let currentName: String

    private var query: String {
        [barcode.trimmed, currentName.trimmed, "product name brand"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var assistantPrompt: String {
        "請依條碼或包裝文字查找最正確的原文商品名稱、品牌、廠商與容量，列出資料來源供我確認：\(query)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("將送出的查詢文字") {
                    Text(query)
                        .textSelection(.enabled)
                }

                Section("查詢方式") {
                    Button("用網頁搜尋", systemImage: "safari") {
                        if let url = webSearchURL { openURL(url) }
                    }
                    ShareLink(item: assistantPrompt) {
                        Label("交給 AI 或搜尋 App", systemImage: "sparkles")
                    }
                }

                Section {
                    Text("只會分享上方文字；不會上傳商品照片、GPS、價格或採買歷史。查詢結果僅供建議，請確認後再填入商品資料。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("查詢外文名稱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var webSearchURL: URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
