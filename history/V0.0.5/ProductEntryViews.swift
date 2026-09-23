import SwiftData
import SwiftUI
import UIKit

struct NewProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]

    let barcode: String
    let onSaved: (Product) -> Void

    @State private var name = ""
    @State private var recordedAt = Date.now
    @State private var store = ""
    @State private var storeBranch = ""
    @State private var city = ""
    @State private var district = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var priceText = ""
    @State private var purchaseQuantityText = "1"
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
                    purchaseQuantityText: $purchaseQuantityText,
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
        .onChange(of: locationRecorder.suggestedCity) { _, value in
            if !value.isEmpty { city = value }
        }
        .onChange(of: locationRecorder.suggestedDistrict) { _, value in
            if !value.isEmpty { district = value }
        }
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty &&
        !store.trimmed.isEmpty &&
        (parsedNumber(amountText) ?? 0) > 0 &&
        !unit.trimmed.isEmpty &&
        (parsedPositiveInteger(purchaseQuantityText) ?? 0) > 0 &&
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
            let purchaseQuantity = parsedPositiveInteger(purchaseQuantityText),
            let price = parsedNumber(priceText), price >= 0
        else {
            errorMessage = "容（重）量與購買數量必須大於 0，購買數量須為整數，價格不可小於 0。"
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
                purchaseQuantity: purchaseQuantity,
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
            onSaved(product)
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
    @State private var purchaseQuantityText = "1"
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

                Section("價格記憶助手") {
                    PriceMemoryDetails(product: product)
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
                    purchaseQuantityText: $purchaseQuantityText,
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
        .onChange(of: locationRecorder.suggestedCity) { _, value in
            if !value.isEmpty { city = value }
        }
        .onChange(of: locationRecorder.suggestedDistrict) { _, value in
            if !value.isEmpty { district = value }
        }
    }

    private var isValid: Bool {
        !store.trimmed.isEmpty &&
        (parsedNumber(amountText) ?? 0) > 0 &&
        !unit.trimmed.isEmpty &&
        (parsedPositiveInteger(purchaseQuantityText) ?? 0) > 0 &&
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
            let purchaseQuantity = parsedPositiveInteger(purchaseQuantityText),
            let price = parsedNumber(priceText), price >= 0
        else {
            errorMessage = "容（重）量與購買數量必須大於 0，購買數量須為整數，價格不可小於 0。"
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
            purchaseQuantity: purchaseQuantity,
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
    @Binding var purchaseQuantityText: String
    @Binding var isOnSale: Bool
    @Binding var isBuyOneGetOne: Bool
    let storePresets: [StorePreset]

    var body: some View {
        Section {
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
            TextField("本次付款總價", text: $priceText)
                .keyboardType(.decimalPad)
            TextField("購買數量", text: $purchaseQuantityText)
                .keyboardType(.numberPad)
            Toggle("特價", isOn: $isOnSale)
            Toggle("買一送一", isOn: $isBuyOneGetOne)
        } header: {
            Text("本次採買")
        } footer: {
            Text("付款總價會依購買數量換算成每件有效單價；買一送一再以實際取得雙倍件數計算。")
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
            Text("GPS 成功時會自動帶入縣市與行政區，欄位仍可手動修改；無法定位時仍可儲存。")
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

private func parsedPositiveInteger(_ text: String) -> Int? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let number = Int(value), number > 0 else { return nil }
    return number
}

struct PriceMemoryDetails: View {
    let product: Product

    var body: some View {
        if let statistics = product.priceStatistics {
            LabeledContent(
                "歷史最低有效單價",
                value: currency(statistics.lowestRecord.effectiveUnitPrice)
            )
            LabeledContent("最便宜店家", value: statistics.lowestRecord.storeDisplayName)
            LabeledContent(
                "最低價時間",
                value: statistics.lowestRecord.recordedAt.formatted(date: .numeric, time: .shortened)
            )
            LabeledContent(
                "歷史平均有效單價",
                value: currency(statistics.averageEffectivePrice)
            )
            LabeledContent(
                "歷史最高有效單價",
                value: currency(statistics.highestRecord.effectiveUnitPrice)
            )
            LabeledContent("最高價店家", value: statistics.highestRecord.storeDisplayName)
            LabeledContent(
                "最高價時間",
                value: statistics.highestRecord.recordedAt.formatted(date: .numeric, time: .shortened)
            )

            if
                let latest = product.latestRecord,
                let pricePerHundred = latest.pricePerHundred,
                let unit = latest.normalizedUnitLabel
            {
                LabeledContent("最新每 100 \(unit)", value: currency(pricePerHundred))
            }

            if
                let lowestNormalized = statistics.lowestNormalizedRecord,
                let pricePerHundred = lowestNormalized.pricePerHundred,
                let unit = lowestNormalized.normalizedUnitLabel
            {
                LabeledContent("歷史最低每 100 \(unit)", value: currency(pricePerHundred))
            }

            Text("有效單價會以購買數量換算；勾選買一送一時，再以實際取得雙倍數量計算。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("建立第一筆採買紀錄後即可比較價格。")
                .foregroundStyle(.secondary)
        }
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "TWD"))
    }
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
