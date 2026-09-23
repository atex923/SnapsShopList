import SwiftData
import SwiftUI
import UIKit

struct NewProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]

    let barcode: String
    let onSaved: (String) -> Void

    @State private var name = ""
    @State private var recordedAt = Date.now
    @State private var store = ""
    @State private var storeBranch = ""
    @State private var city = ""
    @State private var district = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var priceText = ""
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [UIImage] = []
    @State private var errorMessage = ""
    @StateObject private var locationRecorder = LocationRecorder()

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
                    storeBranch: $storeBranch,
                    city: $city,
                    district: $district,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets
                )

                GPSLocationSection(recorder: locationRecorder)

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
        .task { locationRecorder.requestLocation() }
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty &&
        !store.trimmed.isEmpty &&
        (parsedNumber(amountText) ?? 0) > 0 &&
        !unit.trimmed.isEmpty &&
        (parsedNumber(priceText) ?? -1) >= 0
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    private func save() {
        guard
            let amount = parsedNumber(amountText), amount > 0,
            let price = parsedNumber(priceText), price >= 0
        else {
            errorMessage = "容（重）量必須大於 0，價格不可小於 0。"
            return
        }

        var savedFileNames: [String] = []
        do {
            let scannedBarcode = barcode
            var descriptor = FetchDescriptor<Product>(
                predicate: #Predicate<Product> { product in
                    product.barcode == scannedBarcode
                }
            )
            descriptor.fetchLimit = 1
            guard try modelContext.fetch(descriptor).isEmpty else {
                errorMessage = "這個條碼已經建立，請關閉後重新掃描。"
                return
            }

            let product = Product(barcode: barcode, name: name.trimmed)
            let record = PurchaseRecord(
                recordedAt: recordedAt,
                store: store.trimmed,
                storeBranch: storeBranch.trimmed,
                city: city.trimmed,
                district: district.trimmed,
                price: price,
                amount: amount,
                unit: unit.trimmed,
                isOnSale: isOnSale,
                isBuyOneGetOne: isBuyOneGetOne,
                latitude: locationRecorder.location?.coordinate.latitude,
                longitude: locationRecorder.location?.coordinate.longitude,
                locationAccuracy: locationRecorder.location?.horizontalAccuracy,
                product: product
            )
            modelContext.insert(product)
            modelContext.insert(record)
            try rememberStore(
                name: store,
                branch: storeBranch,
                city: city,
                district: district,
                usedAt: recordedAt,
                in: modelContext
            )
            savedFileNames = try persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            draftPhotos.forEach(ProductPhotoStore.saveToPhotoLibrary)
            onSaved(product.name)
            dismiss()
        } catch {
            modelContext.rollback()
            savedFileNames.forEach(ProductPhotoStore.delete)
            AppErrorLogger.record(error, category: "資料儲存", context: "建立商品 \(barcode)")
            errorMessage = error.localizedDescription
        }
    }
}

struct NewPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @Bindable var product: Product
    let onSaved: () -> Void

    @State private var recordedAt = Date.now
    @State private var store = ""
    @State private var storeBranch = ""
    @State private var city = ""
    @State private var district = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var priceText = ""
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [UIImage] = []
    @State private var errorMessage = ""
    @StateObject private var locationRecorder = LocationRecorder()

    init(product: Product, onSaved: @escaping () -> Void) {
        self.product = product
        self.onSaved = onSaved

        if let latest = product.latestRecord {
            _store = State(initialValue: latest.store)
            _storeBranch = State(initialValue: latest.storeBranch)
            _city = State(initialValue: latest.city)
            _district = State(initialValue: latest.district)
            _amountText = State(initialValue: inputNumber(latest.amount))
            _unit = State(initialValue: latest.unit)
            _priceText = State(initialValue: inputNumber(latest.price))
        }
    }

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
                    storeBranch: $storeBranch,
                    city: $city,
                    district: $district,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets
                )

                GPSLocationSection(recorder: locationRecorder)

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
        .task { locationRecorder.requestLocation() }
    }

    private var isValid: Bool {
        !store.trimmed.isEmpty &&
        (parsedNumber(amountText) ?? 0) > 0 &&
        !unit.trimmed.isEmpty &&
        (parsedNumber(priceText) ?? -1) >= 0
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    private func save() {
        guard
            let amount = parsedNumber(amountText), amount > 0,
            let price = parsedNumber(priceText), price >= 0
        else {
            errorMessage = "容（重）量必須大於 0，價格不可小於 0。"
            return
        }

        let record = PurchaseRecord(
            recordedAt: recordedAt,
            store: store.trimmed,
            storeBranch: storeBranch.trimmed,
            city: city.trimmed,
            district: district.trimmed,
            price: price,
            amount: amount,
            unit: unit.trimmed,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            latitude: locationRecorder.location?.coordinate.latitude,
            longitude: locationRecorder.location?.coordinate.longitude,
            locationAccuracy: locationRecorder.location?.horizontalAccuracy,
            product: product
        )

        var savedFileNames: [String] = []
        do {
            modelContext.insert(record)
            try rememberStore(
                name: store,
                branch: storeBranch,
                city: city,
                district: district,
                usedAt: recordedAt,
                in: modelContext
            )
            savedFileNames = try persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            draftPhotos.forEach(ProductPhotoStore.saveToPhotoLibrary)
            onSaved()
            dismiss()
        } catch {
            modelContext.rollback()
            savedFileNames.forEach(ProductPhotoStore.delete)
            AppErrorLogger.record(error, category: "資料儲存", context: "新增採買 \(product.barcode)")
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseFieldsSection: View {
    @Binding var recordedAt: Date
    @Binding var store: String
    @Binding var storeBranch: String
    @Binding var city: String
    @Binding var district: String
    @Binding var amountText: String
    @Binding var unit: String
    @Binding var priceText: String
    @Binding var isOnSale: Bool
    @Binding var isBuyOneGetOne: Bool
    let storePresets: [StorePreset]

    var body: some View {
        Section("本次採買") {
            DatePicker(
                "紀錄時間",
                selection: $recordedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            if !storePresets.isEmpty {
                Menu {
                    ForEach(Array(storePresets.prefix(12))) { preset in
                        Button(preset.displayName) {
                            store = preset.name
                            storeBranch = preset.branch
                            city = preset.city
                            district = preset.district
                        }
                    }
                } label: {
                    Label("選擇曾輸入的店家", systemImage: "clock.arrow.circlepath")
                }
            }
            TextField("店家名稱", text: $store)
            TextField("分店，例如：信義店", text: $storeBranch)
            TextField("縣市，例如：台北市", text: $city)
            TextField("行政區，例如：信義區", text: $district)
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

private struct GPSLocationSection: View {
    @ObservedObject var recorder: LocationRecorder

    var body: some View {
        Section {
            Label(
                recorder.statusText,
                systemImage: recorder.location == nil ? "location.slash" : "location.fill"
            )
            .foregroundStyle(recorder.location == nil ? .secondary : AppTheme.accent)

            if let location = recorder.location {
                LabeledContent(
                    "座標",
                    value: String(
                        format: "%.6f, %.6f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    )
                )
                .font(.caption)
            }

            Button("重新取得定位", systemImage: "location.circle") {
                recorder.requestLocation()
            }
            .disabled(recorder.isLocating)
        } header: {
            Text("GPS 紀錄")
        } footer: {
            Text("未授權或無法定位時仍可儲存，其 GPS 欄位會保留空白。")
        }
    }
}

private struct DraftPhotosSection: View {
    var title = "商品照片"
    var existingPhotoCount = 0
    @Binding var images: [UIImage]
    @State private var isCameraPresented = false
    @State private var isCameraUnavailable = false

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
                if ProductPhotoStore.isCameraAvailable {
                    isCameraPresented = true
                } else {
                    isCameraUnavailable = true
                }
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
        .alert("無法使用相機", isPresented: $isCameraUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("這台裝置沒有可用的相機，請改用 iPhone 實機測試。")
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
            let imageData = try ProductPhotoStore.jpegData(for: image)
            let fileName = try ProductPhotoStore.save(imageData)
            savedFileNames.append(fileName)
            context.insert(ProductPhoto(
                fileName: fileName,
                imageData: imageData,
                product: product
            ))
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

private func parsedNumber(_ text: String) -> Double? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    if let number = formatter.number(from: value) {
        return number.doubleValue
    }

    return Double(value.replacingOccurrences(of: ",", with: "."))
}

private func inputNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}

private func rememberStore(
    name: String,
    branch: String,
    city: String,
    district: String,
    usedAt: Date,
    in context: ModelContext
) throws {
    let storeName = name.trimmed
    let storeBranch = branch.trimmed
    let storeCity = city.trimmed
    let storeDistrict = district.trimmed
    guard !storeName.isEmpty else { return }

    let presets = try context.fetch(FetchDescriptor<StorePreset>())
    let existing = presets.first { preset in
        preset.name.compare(storeName, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame &&
        preset.branch.compare(storeBranch, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame &&
        preset.city.compare(storeCity, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame &&
        preset.district.compare(storeDistrict, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }

    if let existing {
        existing.lastUsedAt = usedAt
        existing.useCount += 1
    } else {
        context.insert(StorePreset(
            name: storeName,
            branch: storeBranch,
            city: storeCity,
            district: storeDistrict,
            lastUsedAt: usedAt
        ))
    }
}
