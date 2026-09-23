import SwiftData
import SwiftUI
import UIKit

struct NewProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @Query(sort: \Product.createdAt, order: .reverse) private var existingProducts: [Product]
    @AppStorage("SnapsShopList.defaultCurrencyCode") private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue

    let barcode: String
    let isManualProduct: Bool
    let onUseExisting: ((Product) -> Void)?
    let onSaved: (Product) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var manufacturerName = ""
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
    @State private var draftPhotos: [Data] = []
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @StateObject private var locationRecorder = LocationRecorder()

    init(
        barcode: String,
        isManualProduct: Bool = false,
        onUseExisting: ((Product) -> Void)? = nil,
        onSaved: @escaping (Product) -> Void
    ) {
        self.barcode = barcode
        self.isManualProduct = isManualProduct
        self.onUseExisting = onUseExisting
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    if isManualProduct {
                        Label("無條碼商品", systemImage: "tag.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("條碼", value: barcode)
                    }
                    TextField("名稱", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("品牌（選填）", text: $brand)
                    TextField("廠商（選填）", text: $manufacturerName)
                }

                if !similarProducts.isEmpty {
                    Section {
                        ForEach(similarProducts) { product in
                            Button {
                                onUseExisting?(product)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(product.name)
                                            .foregroundStyle(.primary)
                                        Text(product.barcodeDisplayText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("使用既有商品")
                                        .font(.caption.bold())
                                }
                            }
                        }
                    } header: {
                        Text("可能已存在的商品")
                    } footer: {
                        Text("若不是同一項商品，可繼續填寫並建立新品。")
                    }
                }

                DraftPhotosSection(images: $draftPhotos) { openCamera() }

                PurchaseFieldsSection(
                    recordedAt: $recordedAt,
                    store: $store,
                    storeBranch: $storeBranch,
                    city: $city,
                    district: $district,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    currencyCode: $defaultCurrencyCode,
                    purchaseQuantityText: $purchaseQuantityText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets
                )

                GPSLocationSection(recorder: locationRecorder, city: $city, district: $district)
            }
            .navigationTitle(isManualProduct ? "建立無條碼商品" : "建立商品資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveMode.title) { Task { await save() } }
                        .disabled(!saveMode.isEnabled || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("隱藏鍵盤", systemImage: "keyboard.chevron.compact.down") {
                        hideKeyboard()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCameraPresented || isSaving)
        .alert("無法儲存", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data in
                guard draftPhotos.count < 3 else {
                    isCameraPresented = false
                    return
                }
                draftPhotos.append(data)
                saveCapturedPhotoToLibrary(data)
                isCameraPresented = false
            }, onCancel: {
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SNAPS_DISABLE_LOCATION"] != "1" {
                locationRecorder.requestLocation()
            }
            #else
            locationRecorder.requestLocation()
            #endif
        }
        .onChange(of: locationRecorder.suggestedCity) { _, value in
            if !value.isEmpty { city = value }
        }
        .onChange(of: locationRecorder.suggestedDistrict) { _, value in
            if !value.isEmpty { district = value }
        }
    }

    private var saveMode: PurchaseSaveMode {
        PurchaseSaveMode.evaluate(
            draft: purchaseDraft,
            requiresProductName: true,
            hasPhotoForDraft: !draftPhotos.isEmpty
        )
    }

    private var similarProducts: [Product] {
        guard isManualProduct else { return [] }
        let query = name.trimmed
        guard query.count >= 2 else { return [] }
        return Array(existingProducts.lazy.filter { product in
            let candidate = product.name.trimmed
            return !candidate.isEmpty && (
                candidate.localizedStandardContains(query) ||
                query.localizedStandardContains(candidate)
            )
        }.prefix(5))
    }

    private var purchaseDraft: PurchaseDraft {
        PurchaseDraft(
            productName: name, store: store, amountText: amountText, unit: unit,
            priceText: priceText, purchaseQuantityText: purchaseQuantityText
        )
    }

    private var validatedPurchase: ValidatedPurchase? {
        PurchaseValidator.validate(purchaseDraft, requiresProductName: true)
    }

    private var validatedDraft: ValidatedPurchase? {
        PurchaseValidator.validateDraft(purchaseDraft)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    @MainActor
    private func save() async {
        let isDraft = validatedPurchase == nil
        guard saveMode.isEnabled, let values = validatedPurchase ?? validatedDraft else {
            errorMessage = "完整資料需填寫名稱、店家、價格與單位；快速暫存至少要有一張照片及有效價格。"
            return
        }

        isSaving = true
        defer { isSaving = false }
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

            let product = Product(
                barcode: barcode,
                name: name.trimmed,
                brand: brand.trimmed,
                manufacturerName: manufacturerName.trimmed
            )
            let record = PurchaseRecord(
                recordedAt: recordedAt,
                store: store.trimmed,
                storeBranch: storeBranch.trimmed,
                city: city.trimmed,
                district: district.trimmed,
                price: values.price,
                currencyCode: defaultCurrencyCode,
                amount: values.amount,
                unit: unit.trimmed,
                isOnSale: isOnSale,
                isBuyOneGetOne: isBuyOneGetOne,
                isDraft: isDraft,
                purchaseQuantity: values.purchaseQuantity,
                latitude: locationRecorder.location?.coordinate.latitude,
                longitude: locationRecorder.location?.coordinate.longitude,
                locationAccuracy: locationRecorder.location?.horizontalAccuracy,
                product: product
            )
            modelContext.insert(product)
            modelContext.insert(record)
            if !store.trimmed.isEmpty {
                try rememberStore(
                    name: store,
                    branch: storeBranch,
                    city: city,
                    district: district,
                    usedAt: recordedAt,
                    in: modelContext
                )
            }
            await persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            onSaved(product)
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料儲存", context: "建立商品 \(barcode)")
            errorMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            errorMessage = "這台裝置沒有可用的相機，請改用 iPhone 實機測試。"
            return
        }
        isCameraPresented = true
    }

    private func saveCapturedPhotoToLibrary(_ data: Data) {
        ProductPhotoStore.saveToPhotoLibrary(data) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }
}

struct NewPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @AppStorage("SnapsShopList.defaultCurrencyCode") private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue
    @Bindable var product: Product
    let onSaved: () -> Void

    @State private var recordedAt = Date.now
    @State private var brand = ""
    @State private var manufacturerName = ""
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
    @State private var draftPhotos: [Data] = []
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var isPriceMemoryExpanded = false
    @State private var photoBeingReplaced: ProductPhoto?
    @State private var photoPendingDeletion: ProductPhoto?
    @StateObject private var locationRecorder = LocationRecorder()

    init(product: Product, onSaved: @escaping () -> Void) {
        self.product = product
        self.onSaved = onSaved
        _brand = State(initialValue: product.brand)
        _manufacturerName = State(initialValue: product.manufacturerName)

        if let latest = product.latestRecord {
            _city = State(initialValue: latest.city)
            _district = State(initialValue: latest.district)
            _amountText = State(initialValue: latest.amount > 0 ? inputNumber(latest.amount) : "")
            _unit = State(initialValue: latest.unit)
            _purchaseQuantityText = State(initialValue: String(latest.purchaseQuantity))
            _isOnSale = State(initialValue: latest.isOnSale)
            _isBuyOneGetOne = State(initialValue: latest.isBuyOneGetOne)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("名稱", value: product.name)
                    LabeledContent("識別", value: product.barcodeDisplayText)
                    TextField("品牌（選填）", text: $brand)
                    TextField("廠商（選填）", text: $manufacturerName)
                }

                EditablePurchasePhotosSection(
                    existingPhotos: product.sortedPhotos,
                    newImages: $draftPhotos,
                    onAdd: {
                        photoBeingReplaced = nil
                        openCamera()
                    },
                    onReplace: { photo in
                        photoBeingReplaced = photo
                        openCamera()
                    },
                    onDelete: { photo in
                        photoPendingDeletion = photo
                    }
                )

                PurchaseFieldsSection(
                    recordedAt: $recordedAt,
                    store: $store,
                    storeBranch: $storeBranch,
                    city: $city,
                    district: $district,
                    amountText: $amountText,
                    unit: $unit,
                    priceText: $priceText,
                    currencyCode: $defaultCurrencyCode,
                    purchaseQuantityText: $purchaseQuantityText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets,
                    prioritizesPriceAndStore: true
                )

                GPSLocationSection(recorder: locationRecorder, city: $city, district: $district)

                Section {
                    DisclosureGroup("價格記憶助手", isExpanded: $isPriceMemoryExpanded) {
                        PriceMemoryDetails(product: product, currencyCode: defaultCurrencyCode)
                            .padding(.leading, 14)
                    }
                }
            }
            .navigationTitle("新增採買紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") { Task { await save() } }
                        .disabled(!saveMode.isEnabled || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("隱藏鍵盤", systemImage: "keyboard.chevron.compact.down") {
                        hideKeyboard()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCameraPresented || isSaving)
        .alert("無法儲存", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data in
                let replacement = photoBeingReplaced
                photoBeingReplaced = nil
                isCameraPresented = false
                if let replacement {
                    Task { await replacePhoto(replacement, with: data) }
                } else {
                    guard product.sortedPhotos.count + draftPhotos.count < 3 else { return }
                    draftPhotos.append(data)
                    saveCapturedPhotoToLibrary(data)
                }
            }, onCancel: {
                photoBeingReplaced = nil
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "刪除這張商品照片？",
            isPresented: Binding(
                get: { photoPendingDeletion != nil },
                set: { if !$0 { photoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除照片", role: .destructive) {
                if let photo = photoPendingDeletion { deletePhoto(photo) }
            }
            Button("取消", role: .cancel) { photoPendingDeletion = nil }
        } message: {
            Text("照片會從商品資料中刪除，此動作無法復原。")
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SNAPS_DISABLE_LOCATION"] != "1" {
                locationRecorder.requestLocation()
            }
            #else
            locationRecorder.requestLocation()
            #endif
        }
        .onChange(of: locationRecorder.suggestedCity) { _, value in
            if !value.isEmpty { city = value }
        }
        .onChange(of: locationRecorder.suggestedDistrict) { _, value in
            if !value.isEmpty { district = value }
        }
    }

    private var saveMode: PurchaseSaveMode {
        PurchaseSaveMode.evaluate(
            draft: purchaseDraft,
            requiresProductName: false,
            hasPhotoForDraft: !product.sortedPhotos.isEmpty || !draftPhotos.isEmpty
        )
    }

    private var purchaseDraft: PurchaseDraft {
        PurchaseDraft(
            store: store, amountText: amountText, unit: unit,
            priceText: priceText, purchaseQuantityText: purchaseQuantityText
        )
    }

    private var validatedPurchase: ValidatedPurchase? {
        PurchaseValidator.validate(purchaseDraft, requiresProductName: false)
    }

    private var validatedDraft: ValidatedPurchase? {
        PurchaseValidator.validateDraft(purchaseDraft)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )
    }

    @MainActor
    private func save() async {
        let isDraft = validatedPurchase == nil
        guard saveMode.isEnabled, let values = validatedPurchase ?? validatedDraft else {
            errorMessage = "完整資料需填寫店家、價格與單位；快速暫存至少要有一張照片及有效價格。"
            return
        }

        let record = PurchaseRecord(
            recordedAt: recordedAt,
            store: store.trimmed,
            storeBranch: storeBranch.trimmed,
            city: city.trimmed,
            district: district.trimmed,
            price: values.price,
            currencyCode: defaultCurrencyCode,
            amount: values.amount,
            unit: unit.trimmed,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            isDraft: isDraft,
            purchaseQuantity: values.purchaseQuantity,
            latitude: locationRecorder.location?.coordinate.latitude,
            longitude: locationRecorder.location?.coordinate.longitude,
            locationAccuracy: locationRecorder.location?.horizontalAccuracy,
            product: product
        )

        isSaving = true
        defer { isSaving = false }
        do {
            product.brand = brand.trimmed
            product.manufacturerName = manufacturerName.trimmed
            modelContext.insert(record)
            if !store.trimmed.isEmpty {
                try rememberStore(
                    name: store,
                    branch: storeBranch,
                    city: city,
                    district: district,
                    usedAt: recordedAt,
                    in: modelContext
                )
            }
            await persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            onSaved()
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料儲存", context: "新增採買 \(product.barcode)")
            errorMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            errorMessage = "這台裝置沒有可用的相機，請改用 iPhone 實機測試。"
            return
        }
        isCameraPresented = true
    }

    private func saveCapturedPhotoToLibrary(_ data: Data) {
        ProductPhotoStore.saveToPhotoLibrary(data) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func replacePhoto(_ photo: ProductPhoto, with sourceData: Data) async {
        do {
            let imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            let legacyFileName = photo.fileName
            photo.imageData = imageData
            photo.fileName = ""
            photo.createdAt = .now
            try modelContext.save()
            ProductPhotoStore.delete(fileName: legacyFileName)
            saveCapturedPhotoToLibrary(sourceData)
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片更新", context: product.barcode)
            errorMessage = error.localizedDescription
        }
    }

    private func deletePhoto(_ photo: ProductPhoto) {
        let legacyFileName = photo.fileName
        modelContext.delete(photo)
        do {
            try modelContext.save()
            ProductPhotoStore.delete(fileName: legacyFileName)
            photoPendingDeletion = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片刪除", context: product.barcode)
            errorMessage = error.localizedDescription
        }
    }
}

struct EditPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @Bindable var record: PurchaseRecord

    @State private var productName: String
    @State private var brand: String
    @State private var manufacturerName: String
    @State private var recordedAt: Date
    @State private var store: String
    @State private var storeBranch: String
    @State private var city: String
    @State private var district: String
    @State private var amountText: String
    @State private var unit: String
    @State private var priceText: String
    @State private var currencyCode: String
    @State private var purchaseQuantityText: String
    @State private var isOnSale: Bool
    @State private var isBuyOneGetOne: Bool
    @State private var errorMessage = ""
    @State private var isSaving = false

    init(record: PurchaseRecord) {
        self.record = record
        _productName = State(initialValue: record.product?.name ?? "")
        _brand = State(initialValue: record.product?.brand ?? "")
        _manufacturerName = State(initialValue: record.product?.manufacturerName ?? "")
        _recordedAt = State(initialValue: record.recordedAt)
        _store = State(initialValue: record.store)
        _storeBranch = State(initialValue: record.storeBranch)
        _city = State(initialValue: record.city)
        _district = State(initialValue: record.district)
        _amountText = State(initialValue: record.amount > 0 ? inputNumber(record.amount) : "")
        _unit = State(initialValue: record.unit)
        _priceText = State(initialValue: inputNumber(record.price))
        _currencyCode = State(initialValue: record.normalizedCurrencyCode)
        _purchaseQuantityText = State(initialValue: String(record.purchaseQuantity))
        _isOnSale = State(initialValue: record.isOnSale)
        _isBuyOneGetOne = State(initialValue: record.isBuyOneGetOne)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("名稱", text: $productName)
                    TextField("品牌（選填）", text: $brand)
                    TextField("廠商（選填）", text: $manufacturerName)
                    LabeledContent("識別", value: record.product?.barcodeDisplayText ?? "")
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
                    currencyCode: $currencyCode,
                    purchaseQuantityText: $purchaseQuantityText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets
                )

                Section("GPS／地區") {
                    if let latitude = record.latitude, let longitude = record.longitude {
                        LabeledContent("座標", value: String(format: "%.6f, %.6f", latitude, longitude))
                            .font(.caption)
                    }
                    TextField("縣市，例如：台北市", text: $city)
                    TextField("行政區，例如：信義區", text: $district)
                }
            }
            .navigationTitle("編輯採買資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveMode.title) { save() }
                        .disabled(!saveMode.isEnabled || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("隱藏鍵盤", systemImage: "keyboard.chevron.compact.down") {
                        hideKeyboard()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("無法儲存", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var draft: PurchaseDraft {
        PurchaseDraft(
            productName: productName,
            store: store,
            amountText: amountText,
            unit: unit,
            priceText: priceText,
            purchaseQuantityText: purchaseQuantityText
        )
    }

    private var validatedPurchase: ValidatedPurchase? {
        PurchaseValidator.validate(draft, requiresProductName: true)
    }

    private var validatedDraft: ValidatedPurchase? {
        PurchaseValidator.validateDraft(draft)
    }

    private var saveMode: PurchaseSaveMode {
        PurchaseSaveMode.evaluate(
            draft: draft,
            requiresProductName: true,
            hasPhotoForDraft: true
        )
    }

    private func save() {
        let isDraft = validatedPurchase == nil
        guard let values = validatedPurchase ?? validatedDraft else {
            errorMessage = "價格與購買數量格式不正確。"
            return
        }

        isSaving = true
        defer { isSaving = false }
        record.product?.name = productName.trimmed
        record.product?.brand = brand.trimmed
        record.product?.manufacturerName = manufacturerName.trimmed
        record.recordedAt = recordedAt
        record.store = store.trimmed
        record.storeBranch = storeBranch.trimmed
        record.city = city.trimmed
        record.district = district.trimmed
        record.price = values.price
        record.currencyCode = SupportedCurrency.normalized(currencyCode).rawValue
        record.amount = values.amount
        record.unit = unit.trimmed
        record.purchaseQuantity = values.purchaseQuantity
        record.isOnSale = isOnSale
        record.isBuyOneGetOne = isBuyOneGetOne
        record.isDraft = isDraft

        do {
            if !store.trimmed.isEmpty {
                try rememberStore(
                    name: store,
                    branch: storeBranch,
                    city: city,
                    district: district,
                    usedAt: recordedAt,
                    in: modelContext
                )
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料編輯", context: record.product?.barcode ?? "")
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
    @Binding var currencyCode: String
    @Binding var purchaseQuantityText: String
    @Binding var isOnSale: Bool
    @Binding var isBuyOneGetOne: Bool
    let storePresets: [StorePreset]
    var prioritizesPriceAndStore = false

    var body: some View {
        Section {
            if prioritizesPriceAndStore {
                priceField
                storePresetMenu
                storeFields
                Toggle("特價", isOn: $isOnSale)
                Toggle("買一送一", isOn: $isBuyOneGetOne)
                remainingFields
                recordedAtField
            } else {
                recordedAtField
                storePresetMenu
                storeFields
                priceField
                remainingFields
                Toggle("特價", isOn: $isOnSale)
                Toggle("買一送一", isOn: $isBuyOneGetOne)
            }
        } header: {
            Text("本次採買")
        } footer: {
            Text("分店與容量可不填。付款總價會依購買數量換算成每件有效單價；買一送一再以實際取得雙倍件數計算。")
        }
    }

    private var recordedAtField: some View {
        DatePicker(
            "紀錄時間",
            selection: $recordedAt,
            displayedComponents: [.date, .hourAndMinute]
        )
    }

    @ViewBuilder
    private var storePresetMenu: some View {
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
                Label("選擇曾輸入的店家與分店", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var storeFields: some View {
        Group {
            TextField("店家名稱", text: $store)
            TextField("分店，例如：信義店", text: $storeBranch)
        }
    }

    private var priceField: some View {
        Group {
            TextField("本次付款總價", text: $priceText)
                .keyboardType(.decimalPad)
            Picker("貨幣", selection: $currencyCode) {
                ForEach(SupportedCurrency.allCases) { currency in
                    Text(currency.displayName).tag(currency.rawValue)
                }
            }
        }
    }

    private var remainingFields: some View {
        Group {
            TextField("購買數量", text: $purchaseQuantityText)
                .keyboardType(.numberPad)
            TextField("單位，例如：g、ml、包", text: $unit)
            TextField("容量／實際重量（選填）", text: $amountText)
                .keyboardType(.decimalPad)
        }
    }
}

private struct GPSLocationSection: View {
    @ObservedObject var recorder: LocationRecorder
    @Binding var city: String
    @Binding var district: String

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

            TextField("縣市，例如：台北市", text: $city)
            TextField("行政區，例如：信義區", text: $district)

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

private struct EditablePurchasePhotosSection: View {
    let existingPhotos: [ProductPhoto]
    @Binding var newImages: [Data]
    let onAdd: () -> Void
    let onReplace: (ProductPhoto) -> Void
    let onDelete: (ProductPhoto) -> Void

    private var availableCount: Int {
        max(0, 3 - existingPhotos.count - newImages.count)
    }

    var body: some View {
        Section {
            if existingPhotos.isEmpty && newImages.isEmpty {
                Text("尚未拍攝照片")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(existingPhotos) { photo in
                            existingPhoto(photo)
                        }
                        ForEach(Array(newImages.enumerated()), id: \.offset) { index, data in
                            newPhoto(data, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            Button("拍攝商品照片（尚可 \(availableCount) 張）", systemImage: "camera.fill") {
                onAdd()
            }
            .disabled(availableCount == 0)
        } header: {
            Text("商品照片")
        } footer: {
            Text("沿用既有照片；可直接更換或刪除。每項商品最多保存 3 張，新照片也會加入手機相簿。")
        }
    }

    private func existingPhoto(_ photo: ProductPhoto) -> some View {
        ZStack(alignment: .bottom) {
            photoImage(ProductPhotoStore.load(photo: photo))

            HStack {
                Button(role: .destructive) { onDelete(photo) } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .accessibilityLabel("刪除照片")

                Spacer()

                Button { onReplace(photo) } label: {
                    Image(systemName: "arrowtriangle.up.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppTheme.accent)
                }
                .accessibilityLabel("更換照片")
            }
            .font(.title2)
            .padding(6)
        }
    }

    private func newPhoto(_ data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            photoImage(UIImage(data: data))

            Button(role: .destructive) {
                newImages.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            }
            .accessibilityLabel("移除新照片")
            .padding(5)
        }
    }

    private func photoImage(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 124, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DraftPhotosSection: View {
    var title = "商品照片"
    var existingPhotoCount = 0
    @Binding var images: [Data]
    let onOpenCamera: () -> Void

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
                        ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }

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
                onOpenCamera()
            }
            .disabled(availableCount == 0)
        } header: {
            Text(title)
        } footer: {
            Text("每項商品最多保存 3 張，儲存時也會加入手機相簿。")
        }
    }
}

private func persistDraftPhotos(
    _ images: [Data],
    for product: Product,
    in context: ModelContext
) async {
    for sourceData in images {
        do {
            let imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            context.insert(ProductPhoto(fileName: "", imageData: imageData, product: product))
        } catch {
            AppErrorLogger.record(error, category: "照片處理", context: "商品 \(product.barcode)；商品資料繼續儲存")
        }
    }
}

private func inputNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}


private func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

struct PriceMemoryDetails: View {
    let product: Product
    var currencyCode: String? = nil

    var body: some View {
        if let comparisonCurrencyCode,
           let statistics = product.priceStatistics(currencyCode: comparisonCurrencyCode) {
            LabeledContent(
                "比較貨幣",
                value: SupportedCurrency.normalized(statistics.currencyCode).displayName
            )
            LabeledContent(
                "歷史最低有效單價",
                value: currency(statistics.lowestRecord.effectiveUnitPrice, code: statistics.currencyCode)
            )
            LabeledContent("最便宜店家", value: statistics.lowestRecord.storeDisplayName)
            LabeledContent(
                "最低價時間",
                value: statistics.lowestRecord.recordedAt.formatted(date: .numeric, time: .shortened)
            )
            LabeledContent(
                "歷史平均有效單價",
                value: currency(statistics.averageEffectivePrice, code: statistics.currencyCode)
            )
            LabeledContent(
                "歷史最高有效單價",
                value: currency(statistics.highestRecord.effectiveUnitPrice, code: statistics.currencyCode)
            )
            LabeledContent("最高價店家", value: statistics.highestRecord.storeDisplayName)
            LabeledContent(
                "最高價時間",
                value: statistics.highestRecord.recordedAt.formatted(date: .numeric, time: .shortened)
            )

            if
                let pricePerHundred = statistics.latestRecord.pricePerHundred,
                let unit = statistics.latestRecord.normalizedUnitLabel
            {
                LabeledContent("最新每 100 \(unit)", value: currency(pricePerHundred, code: statistics.currencyCode))
            }

            if
                let lowestNormalized = statistics.lowestNormalizedRecord,
                let pricePerHundred = lowestNormalized.pricePerHundred,
                let unit = lowestNormalized.normalizedUnitLabel
            {
                LabeledContent("歷史最低每 100 \(unit)", value: currency(pricePerHundred, code: statistics.currencyCode))
            }

            Text("價格統計只比較相同貨幣。有效單價會依購買數量換算；買一送一再以實際取得雙倍數量計算。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(currencyCode == nil ? "建立第一筆採買紀錄後即可比較價格。" : "這個貨幣尚無歷史價格。")
                .foregroundStyle(.secondary)
        }
    }

    private var comparisonCurrencyCode: String? {
        currencyCode.map { SupportedCurrency.normalized($0).rawValue }
            ?? product.latestRecord?.normalizedCurrencyCode
    }

    private func currency(_ value: Double, code: String) -> String {
        SupportedCurrency.format(value, code: code)
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

    let normalizedKey = StoreIdentity.key(
        name: storeName,
        branch: storeBranch,
        city: storeCity,
        district: storeDistrict
    )
    var descriptor = FetchDescriptor<StorePreset>(
        predicate: #Predicate<StorePreset> { $0.normalizedKey == normalizedKey }
    )
    descriptor.fetchLimit = 1
    let existing = try context.fetch(descriptor).first

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
