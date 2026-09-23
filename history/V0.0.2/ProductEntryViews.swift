import SwiftData
import SwiftUI
import UIKit

struct NewProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let barcode: String
    let onSaved: (String) -> Void

    @State private var name = ""
    @State private var recordedAt = Date.now
    @State private var store = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var priceText = ""
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [UIImage] = []
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("條碼", value: barcode)
                    TextField("名稱", text: $name)
                        .textInputAutocapitalization(.never)
                }

                PurchaseFieldsSection(
                    recordedAt: $recordedAt,
                    store: $store,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne
                )

                DraftPhotosSection(images: $draftPhotos)
            }
            .navigationTitle("建立商品資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .alert("無法儲存", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty &&
        !store.trimmed.isEmpty &&
        Double(amountText) != nil &&
        !unit.trimmed.isEmpty &&
        Double(priceText) != nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    private func save() {
        guard let amount = Double(amountText), let price = Double(priceText) else {
            errorMessage = "容（重）量與價格必須是數字。"
            return
        }

        let product = Product(barcode: barcode, name: name.trimmed)
        let record = PurchaseRecord(
            recordedAt: recordedAt,
            store: store.trimmed,
            price: price,
            amount: amount,
            unit: unit.trimmed,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            product: product
        )

        var savedFileNames: [String] = []
        do {
            modelContext.insert(product)
            modelContext.insert(record)
            savedFileNames = try persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            draftPhotos.forEach(ProductPhotoStore.saveToPhotoLibrary)
            onSaved(product.name)
            dismiss()
        } catch {
            modelContext.rollback()
            savedFileNames.forEach(ProductPhotoStore.delete)
            errorMessage = error.localizedDescription
        }
    }
}

struct NewPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var product: Product
    let onSaved: () -> Void

    @State private var recordedAt = Date.now
    @State private var store = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var priceText = ""
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [UIImage] = []
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("名稱", value: product.name)
                    LabeledContent("條碼", value: product.barcode)
                }

                PurchaseFieldsSection(
                    recordedAt: $recordedAt,
                    store: $store,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne
                )

                DraftPhotosSection(
                    title: "更新商品照片",
                    existingPhotoCount: product.sortedPhotos.count,
                    images: $draftPhotos
                )
            }
            .navigationTitle("新增採買紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .alert("無法儲存", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var isValid: Bool {
        !store.trimmed.isEmpty &&
        Double(amountText) != nil &&
        !unit.trimmed.isEmpty &&
        Double(priceText) != nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    private func save() {
        guard let amount = Double(amountText), let price = Double(priceText) else {
            errorMessage = "容（重）量與價格必須是數字。"
            return
        }

        let record = PurchaseRecord(
            recordedAt: recordedAt,
            store: store.trimmed,
            price: price,
            amount: amount,
            unit: unit.trimmed,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            product: product
        )

        var savedFileNames: [String] = []
        do {
            modelContext.insert(record)
            savedFileNames = try persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            draftPhotos.forEach(ProductPhotoStore.saveToPhotoLibrary)
            onSaved()
            dismiss()
        } catch {
            modelContext.rollback()
            savedFileNames.forEach(ProductPhotoStore.delete)
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseFieldsSection: View {
    @Binding var recordedAt: Date
    @Binding var store: String
    @Binding var amountText: String
    @Binding var unit: String
    @Binding var priceText: String
    @Binding var isOnSale: Bool
    @Binding var isBuyOneGetOne: Bool

    var body: some View {
        Section("本次採買") {
            DatePicker(
                "紀錄時間",
                selection: $recordedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            TextField("店家", text: $store)
            TextField("容（重）量", text: $amountText)
                .keyboardType(.decimalPad)
            TextField("單位，例如：g、ml、包", text: $unit)
            TextField("價格", text: $priceText)
                .keyboardType(.decimalPad)
            Toggle("特價", isOn: $isOnSale)
            Toggle("買一送一", isOn: $isBuyOneGetOne)
        }
    }
}

private struct DraftPhotosSection: View {
    var title = "商品照片"
    var existingPhotoCount = 0
    @Binding var images: [UIImage]
    @State private var isCameraPresented = false

    private var availableCount: Int {
        max(0, 3 - existingPhotoCount - images.count)
    }

    var body: some View {
        Section {
            if images.isEmpty {
                Text(existingPhotoCount > 0 ? "目前已有 \(existingPhotoCount) 張照片" : "尚未拍攝照片")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                Button(role: .destructive) {
                                    images.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .red)
                                }
                                .padding(5)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Button("拍攝商品照片（尚可 \(availableCount) 張）", systemImage: "camera.fill") {
                isCameraPresented = true
            }
            .disabled(availableCount == 0)
        } header: {
            Text(title)
        } footer: {
            Text("每項商品最多保存 3 張，儲存時也會加入手機相簿。")
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraPhotoPicker { image in
                guard existingPhotoCount + images.count < 3 else { return }
                images.append(image)
            }
            .ignoresSafeArea()
        }
    }
}

@discardableResult
private func persistDraftPhotos(
    _ images: [UIImage],
    for product: Product,
    in context: ModelContext
) throws -> [String] {
    var savedFileNames: [String] = []
    do {
        for image in images {
            let fileName = try ProductPhotoStore.save(image)
            savedFileNames.append(fileName)
            context.insert(ProductPhoto(fileName: fileName, product: product))
        }
        return savedFileNames
    } catch {
        savedFileNames.forEach(ProductPhotoStore.delete)
        throw error
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
