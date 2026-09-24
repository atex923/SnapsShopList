import SwiftData
import SwiftUI
import PhotosUI
import UIKit

struct NewProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @Query(sort: \Product.createdAt, order: .reverse) private var existingProducts: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage("SnapsShopList.defaultCurrencyCode") private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue

    let barcode: String
    let isManualProduct: Bool
    let quickDraft: QuickDraft?
    let onUseExisting: ((Product) -> Void)?
    let onSaved: (Product) -> Void

    @State private var name = ""
    @State private var productBarcode: String
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
    @State private var isGroupPackage = false
    @State private var groupContentCountText = "1"
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [Data] = []
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var isBarcodeScannerPresented = false
    @State private var isForeignNameLookupPresented = false
    @State private var barcodeScanNotice = ""
    @StateObject private var locationRecorder = LocationRecorder()

    init(
        barcode: String,
        isManualProduct: Bool = false,
        quickDraft: QuickDraft? = nil,
        onUseExisting: ((Product) -> Void)? = nil,
        onSaved: @escaping (Product) -> Void
    ) {
        self.barcode = barcode
        self.isManualProduct = isManualProduct
        self.quickDraft = quickDraft
        self.onUseExisting = onUseExisting
        self.onSaved = onSaved
        let loadedPhotos = quickDraft.map(QuickDraftStore.photoItems) ?? []
        _productBarcode = State(initialValue: quickDraft?.barcode ?? barcode)
        _name = State(initialValue: quickDraft?.name ?? "")
        _recordedAt = State(initialValue: quickDraft?.recordedAt ?? .now)
        _store = State(initialValue: quickDraft?.store ?? "")
        _city = State(initialValue: quickDraft?.city ?? "")
        _district = State(initialValue: quickDraft?.district ?? "")
        _amountText = State(initialValue: quickDraft?.amountText ?? "")
        _unit = State(initialValue: quickDraft?.unit ?? "")
        _priceText = State(initialValue: quickDraft?.priceText ?? "")
        let draftQuantity = quickDraft?.quantityText ?? ""
        _purchaseQuantityText = State(initialValue: draftQuantity.trimmed.isEmpty ? "1" : draftQuantity)
        _isOnSale = State(initialValue: quickDraft?.isOnSale ?? false)
        _isBuyOneGetOne = State(initialValue: quickDraft?.isBuyOneGetOne ?? false)
        _draftPhotos = State(initialValue: Array(loadedPhotos.prefix(AppLimits.maximumPhotos).map(\.data)))
    }

    var body: some View {
        NavigationStack {
            Form {
                DraftPhotosSection(
                    images: $draftPhotos,
                    onError: { errorMessage = $0 },
                    onOpenCamera: { openCamera() }
                )

                Section("商品") {
                    BarcodeFieldRow(
                        value: ProductIdentifier.isManual(productBarcode) ? "無條碼商品" : productBarcode,
                        onCode: { code in
                            productBarcode = code
                            barcodeScanNotice = "已從照片讀取條碼 \(code)"
                        },
                        onError: { errorMessage = $0 }
                    )
                    if !barcodeScanNotice.isEmpty {
                        Text(barcodeScanNotice)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                    ProductNameField(
                        name: $name,
                        brand: $brand,
                        manufacturerName: $manufacturerName,
                        allowsNameEditing: true,
                        showsOverseasFields: overseasModeEnabled
                    )
                        .textInputAutocapitalization(.never)
                    if overseasModeEnabled {
                        OverseasTextCaptureButton(title: "從包裝擷取商品名稱") { name = $0 }
                        Button("查詢正確外文名稱", systemImage: "globe") {
                            isForeignNameLookupPresented = true
                        }
                    }
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
                    isGroupPackage: $isGroupPackage,
                    groupContentCountText: $groupContentCountText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets,
                    showsOverseasFields: overseasModeEnabled
                )

                GPSLocationSection(recorder: locationRecorder, city: $city, district: $district)
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
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
                    KeyboardDismissButton()
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
            CameraPhotoPicker(onPhotoData: { data, source in
                guard draftPhotos.count < AppLimits.maximumPhotos else {
                    isCameraPresented = false
                    return
                }
                draftPhotos.append(data)
                if source == .camera { saveCapturedPhotoToLibrary(data) }
                isCameraPresented = false
            }, onCancel: {
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isForeignNameLookupPresented) {
            ForeignNameLookupSheet(barcode: productBarcode, currentName: name)
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
            priceText: priceText, purchaseQuantityText: purchaseQuantityText,
            isGroupPackage: isGroupPackage, groupContentCountText: groupContentCountText
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
            let scannedBarcode = productBarcode
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
                barcode: productBarcode,
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
                currencyCode: quickDraft?.currencyCode ?? PurchaseCurrencyPolicy.activeCode(
                    overseasModeEnabled: overseasModeEnabled,
                    preferredCode: defaultCurrencyCode
                ),
                amount: values.amount,
                unit: unit.trimmed,
                isOnSale: isOnSale,
                isBuyOneGetOne: isBuyOneGetOne,
                isDraft: isDraft,
                purchaseQuantity: values.purchaseQuantity,
                isGroupPackage: isGroupPackage,
                groupContentCount: values.groupContentCount,
                latitude: quickDraft?.latitude ?? locationRecorder.location?.coordinate.latitude,
                longitude: quickDraft?.longitude ?? locationRecorder.location?.coordinate.longitude,
                locationAccuracy: quickDraft?.locationAccuracy ?? locationRecorder.location?.horizontalAccuracy,
                product: product,
                recordStatus: isDraft ? .comparison : .complete,
                locationSource: quickDraft?.locationSource ?? (locationRecorder.location == nil ? .none : .liveGPS)
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
            UnitMemory.remember(unit)
            try modelContext.save()
            if let quickDraft { QuickDraftStore.delete(quickDraft) }
            onSaved(product)
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料儲存", context: "建立商品 \(productBarcode)")
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
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage("SnapsShopList.defaultCurrencyCode") private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue
    @Bindable var product: Product
    let quickDraft: QuickDraft?
    let onSaved: () -> Void

    @State private var recordedAt = Date.now
    @State private var productName = ""
    @State private var productBarcode = ""
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
    @State private var isGroupPackage = false
    @State private var groupContentCountText = "1"
    @State private var isOnSale = false
    @State private var isBuyOneGetOne = false
    @State private var draftPhotos: [Data] = []
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var isBarcodeScannerPresented = false
    @State private var isPriceMemoryExpanded = false
    @State private var photoBeingReplaced: ProductPhoto?
    @State private var photoPendingDeletion: ProductPhoto?
    @State private var isForeignNameLookupPresented = false
    @StateObject private var locationRecorder = LocationRecorder()

    init(product: Product, quickDraft: QuickDraft? = nil, onSaved: @escaping () -> Void) {
        self.product = product
        self.quickDraft = quickDraft
        self.onSaved = onSaved
        _productBarcode = State(initialValue: quickDraft?.barcode ?? product.barcode)
        let draftName = quickDraft?.name ?? ""
        _productName = State(initialValue: draftName.trimmed.isEmpty ? product.name : draftName)
        _brand = State(initialValue: product.brand)
        _manufacturerName = State(initialValue: product.manufacturerName)

        let loadedPhotos = quickDraft.map(QuickDraftStore.photoItems) ?? []
        _draftPhotos = State(initialValue: Array(loadedPhotos.prefix(AppLimits.maximumPhotos).map(\.data)))

        if let quickDraft {
            _recordedAt = State(initialValue: quickDraft.recordedAt)
            _store = State(initialValue: quickDraft.store)
            _city = State(initialValue: quickDraft.city)
            _district = State(initialValue: quickDraft.district)
            _amountText = State(initialValue: quickDraft.amountText)
            _unit = State(initialValue: quickDraft.unit)
            _priceText = State(initialValue: quickDraft.priceText)
            _purchaseQuantityText = State(initialValue: quickDraft.quantityText.trimmed.isEmpty ? "1" : quickDraft.quantityText)
            _isOnSale = State(initialValue: quickDraft.isOnSale)
            _isBuyOneGetOne = State(initialValue: quickDraft.isBuyOneGetOne)
        } else if let latest = product.latestRecord {
            _amountText = State(initialValue: latest.amount > 0 ? inputNumber(latest.amount) : "")
            _unit = State(initialValue: latest.unit)
            _isGroupPackage = State(initialValue: latest.isGroupPackage)
            _groupContentCountText = State(initialValue: String(latest.groupContentCount))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                CompactNewPurchaseCard(
                    product: product,
                    productName: productName,
                    productBarcode: productBarcode,
                    draftPhotos: $draftPhotos,
                    priceText: $priceText,
                    purchaseQuantityText: $purchaseQuantityText,
                    onOpenCamera: {
                        photoBeingReplaced = product.sortedPhotos.first
                        openCamera()
                    },
                    onPhotoData: { data in
                        if let photo = product.sortedPhotos.first {
                            Task { await replacePhoto(photo, with: data, saveToLibrary: false) }
                        } else if draftPhotos.isEmpty {
                            draftPhotos.append(data)
                        } else {
                            draftPhotos[0] = data
                        }
                    },
                    onError: { errorMessage = $0 }
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
                    isGroupPackage: $isGroupPackage,
                    groupContentCountText: $groupContentCountText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets,
                    showsOverseasFields: overseasModeEnabled,
                    prefersCurrentPurchaseFirst: true,
                    showsRecordedAt: false,
                    showsPriceAndQuantity: false
                )

                Section {
                    DatePicker(
                        "紀錄時間",
                        selection: $recordedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                GPSLocationSection(recorder: locationRecorder, city: $city, district: $district)
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
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
                    KeyboardDismissButton()
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
            CameraPhotoPicker(onPhotoData: { data, source in
                let replacement = photoBeingReplaced
                photoBeingReplaced = nil
                isCameraPresented = false
                if let replacement {
                    Task { await replacePhoto(replacement, with: data, saveToLibrary: source == .camera) }
                } else if product.sortedPhotos.isEmpty, !draftPhotos.isEmpty {
                    draftPhotos[0] = data
                    if source == .camera { saveCapturedPhotoToLibrary(data) }
                } else {
                    guard product.sortedPhotos.count + draftPhotos.count < AppLimits.maximumPhotos else { return }
                    draftPhotos.append(data)
                    if source == .camera { saveCapturedPhotoToLibrary(data) }
                }
            }, onCancel: {
                photoBeingReplaced = nil
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isBarcodeScannerPresented) {
            BarcodeScannerSheet(onCode: { code in
                productBarcode = code
                isBarcodeScannerPresented = false
            }, onNoBarcode: {
                isBarcodeScannerPresented = false
            })
        }
        .sheet(isPresented: $isForeignNameLookupPresented) {
            ForeignNameLookupSheet(barcode: product.barcodeDisplayText, currentName: productName)
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
            priceText: priceText, purchaseQuantityText: purchaseQuantityText,
            isGroupPackage: isGroupPackage, groupContentCountText: groupContentCountText
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
            currencyCode: quickDraft?.currencyCode ?? PurchaseCurrencyPolicy.activeCode(
                overseasModeEnabled: overseasModeEnabled,
                preferredCode: defaultCurrencyCode
            ),
            amount: values.amount,
            unit: unit.trimmed,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            isDraft: isDraft,
            purchaseQuantity: values.purchaseQuantity,
            isGroupPackage: isGroupPackage,
            groupContentCount: values.groupContentCount,
            latitude: quickDraft?.latitude ?? locationRecorder.location?.coordinate.latitude,
            longitude: quickDraft?.longitude ?? locationRecorder.location?.coordinate.longitude,
            locationAccuracy: quickDraft?.locationAccuracy ?? locationRecorder.location?.horizontalAccuracy,
            product: product,
            recordStatus: isDraft ? .comparison : .complete,
            locationSource: quickDraft?.locationSource ?? (locationRecorder.location == nil ? .none : .liveGPS)
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let normalizedBarcode = productBarcode.trimmed
            if !normalizedBarcode.isEmpty, normalizedBarcode != product.barcode {
                let searchedBarcode = normalizedBarcode
                let descriptor = FetchDescriptor<Product>(
                    predicate: #Predicate<Product> { $0.barcode == searchedBarcode }
                )
                if try modelContext.fetch(descriptor).contains(where: { $0.id != product.id }) {
                    errorMessage = "這個條碼已經屬於另一項商品。"
                    return
                }
                product.barcode = normalizedBarcode
            }
            product.name = productName.trimmed
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
            UnitMemory.remember(unit)
            try modelContext.save()
            if let quickDraft { QuickDraftStore.delete(quickDraft) }
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
    private func replacePhoto(
        _ photo: ProductPhoto,
        with sourceData: Data,
        saveToLibrary: Bool = true
    ) async {
        do {
            let imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            let legacyFileName = photo.fileName
            photo.imageData = imageData
            photo.fileName = ""
            photo.createdAt = .now
            try modelContext.save()
            ProductPhotoStore.delete(fileName: legacyFileName)
            if saveToLibrary { saveCapturedPhotoToLibrary(sourceData) }
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

struct WishlistProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @Query private var products: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage("SnapsShopList.defaultCurrencyCode") private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue

    let barcode: String
    let isManualProduct: Bool
    let onSaved: (Product) -> Void

    @State private var productBarcode: String
    @State private var name = ""
    @State private var priceText = ""
    @State private var store = ""
    @State private var storeBranch = ""
    @State private var draftPhotos: [Data] = []
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var isBarcodeScannerPresented = false
    @State private var barcodeScanNotice = ""

    init(
        barcode: String,
        isManualProduct: Bool = false,
        onSaved: @escaping (Product) -> Void
    ) {
        self.barcode = barcode
        self.isManualProduct = isManualProduct
        self.onSaved = onSaved
        _productBarcode = State(initialValue: barcode)
    }

    var body: some View {
        NavigationStack {
            Form {
                DraftPhotosSection(
                    title: nil,
                    images: $draftPhotos,
                    onError: { errorMessage = $0 },
                    onOpenCamera: { openCamera() }
                )
                WishlistBarcodeField(
                    barcode: $productBarcode,
                    isManualProduct: isManualProduct,
                    onOpenScanner: { isBarcodeScannerPresented = true },
                    onCode: {
                        productBarcode = $0
                        barcodeScanNotice = "已從照片讀取條碼 \($0)"
                    },
                    onError: { errorMessage = $0 }
                )
                if !barcodeScanNotice.isEmpty {
                    Text(barcodeScanNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
                LabeledEntryField("名稱", placeholder: "商品名稱", text: $name, labelWidth: 64)
                FastNumericEntryField(
                    "價格",
                    placeholder: "想買價格（選填）",
                    text: $priceText,
                    keyboardType: .decimalPad,
                    labelWidth: 64
                )
                WishlistStoreField(
                    store: $store,
                    storeBranch: $storeBranch,
                    storePresets: storePresets
                )
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
            .navigationTitle("建立待買商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
        }
        .interactiveDismissDisabled(isCameraPresented || isSaving)
        .alert("無法儲存", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data, source in
                guard draftPhotos.count < AppLimits.maximumPhotos else {
                    isCameraPresented = false
                    return
                }
                draftPhotos.append(data)
                if source == .camera {
                    ProductPhotoStore.saveToPhotoLibrary(data) { result in
                        if case .failure(let error) = result { errorMessage = error.localizedDescription }
                    }
                }
                isCameraPresented = false
            }, onCancel: {
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isBarcodeScannerPresented) {
            BarcodeScannerSheet(onCode: { code in
                productBarcode = code
                barcodeScanNotice = "已拍照掃描條碼 \(code)"
                isBarcodeScannerPresented = false
            }, onNoBarcode: {
                isBarcodeScannerPresented = false
            })
        }
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && parsedOptionalPrice != nil
    }

    private var parsedOptionalPrice: Double? {
        let value = priceText.trimmed
        guard !value.isEmpty else { return 0 }
        guard let price = LocalizedNumberParser.double(from: value), price >= 0 else { return nil }
        return price
    }

    @MainActor
    private func save() async {
        guard canSave, let price = parsedOptionalPrice else {
            errorMessage = "名稱必填；價格若有輸入，需為有效數字。"
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let normalizedBarcode = productBarcode.trimmed.isEmpty ? ProductIdentifier.makeManual() : productBarcode.trimmed
            let existing = try existingProduct(for: normalizedBarcode)
            let product = existing ?? Product(
                barcode: normalizedBarcode,
                name: name.trimmed
            )
            if existing == nil {
                modelContext.insert(product)
            }
            if product.name.trimmed.isEmpty || ProductIdentifier.isManual(product.barcode) {
                product.name = name.trimmed
            }

            if !priceText.trimmed.isEmpty {
                let currencyCode = PurchaseCurrencyPolicy.activeCode(
                    overseasModeEnabled: overseasModeEnabled,
                    preferredCode: defaultCurrencyCode
                )
                let record = PurchaseRecord(
                    recordedAt: .now,
                    store: store.trimmed,
                    storeBranch: storeBranch.trimmed,
                    price: price,
                    currencyCode: currencyCode,
                    amount: 0,
                    unit: "",
                    isOnSale: false,
                    isBuyOneGetOne: false,
                    purchaseQuantity: 1,
                    product: product,
                    recordStatus: .wishlistQuote,
                    quantityWasEntered: true
                )
                modelContext.insert(record)
            }

            if !store.trimmed.isEmpty {
                try rememberStore(
                    name: store,
                    branch: storeBranch,
                    city: "",
                    district: "",
                    usedAt: .now,
                    in: modelContext
                )
            }
            await persistDraftPhotos(draftPhotos, for: product, in: modelContext)
            try modelContext.save()
            onSaved(product)
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "待買清單", context: productBarcode)
            errorMessage = error.localizedDescription
        }
    }

    private func existingProduct(for barcode: String) throws -> Product? {
        guard !ProductIdentifier.isManual(barcode) else { return nil }
        var descriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { $0.barcode == barcode }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            errorMessage = "這台裝置沒有可用的相機，請改用 iPhone 實機測試。"
            return
        }
        isCameraPresented = true
    }
}

struct EditPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @Bindable var record: PurchaseRecord

    @State private var productName: String
    @State private var brand: String
    @State private var manufacturerName: String
    @State private var replacementBarcode: String
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
    @State private var isGroupPackage: Bool
    @State private var groupContentCountText: String
    @State private var isOnSale: Bool
    @State private var isBuyOneGetOne: Bool
    @State private var errorMessage = ""
    @State private var isSaving = false

    init(record: PurchaseRecord) {
        self.record = record
        _productName = State(initialValue: record.product?.name ?? "")
        _brand = State(initialValue: record.product?.brand ?? "")
        _manufacturerName = State(initialValue: record.product?.manufacturerName ?? "")
        _replacementBarcode = State(initialValue: "")
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
        _isGroupPackage = State(initialValue: record.isGroupPackage)
        _groupContentCountText = State(initialValue: String(record.groupContentCount))
        _isOnSale = State(initialValue: record.isOnSale)
        _isBuyOneGetOne = State(initialValue: record.isBuyOneGetOne)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    ProductNameField(
                        name: $productName,
                        brand: $brand,
                        manufacturerName: $manufacturerName,
                        allowsNameEditing: true,
                        showsOverseasFields: overseasModeEnabled
                    )
                    if overseasModeEnabled {
                        OverseasTextCaptureButton(title: "從包裝擷取商品名稱") { productName = $0 }
                    }
                    if record.product?.isManualProduct == true {
                        HStack(spacing: 8) {
                            LabeledEntryField("補登條碼", placeholder: "可稍後輸入正式條碼", text: $replacementBarcode)
                                .keyboardType(.numberPad)
                            BarcodePhotoPickerButton(
                                onCode: { replacementBarcode = $0 },
                                onError: { errorMessage = $0 }
                            )
                        }
                    } else {
                        LabeledContent("識別", value: record.product?.barcodeDisplayText ?? "")
                    }
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
                    isGroupPackage: $isGroupPackage,
                    groupContentCountText: $groupContentCountText,
                    isOnSale: $isOnSale,
                    isBuyOneGetOne: $isBuyOneGetOne,
                    storePresets: storePresets,
                    showsOverseasFields: overseasModeEnabled
                )

                ExistingGPSSection(record: record, city: $city, district: $district)
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
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
                    KeyboardDismissButton()
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
            purchaseQuantityText: purchaseQuantityText,
            isGroupPackage: isGroupPackage,
            groupContentCountText: groupContentCountText
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

        if let product = record.product,
           product.isManualProduct,
           !replacementBarcode.trimmed.isEmpty {
            do {
                let candidate = replacementBarcode.trimmed
                let currentID = product.id
                let descriptor = FetchDescriptor<Product>(
                    predicate: #Predicate<Product> { item in
                        item.barcode == candidate && item.id != currentID
                    }
                )
                guard try modelContext.fetch(descriptor).isEmpty else {
                    errorMessage = "這個條碼已經屬於另一項商品。"
                    return
                }
                product.barcode = candidate
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
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
        record.isGroupPackage = isGroupPackage
        record.groupContentCount = values.groupContentCount
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
            UnitMemory.remember(unit)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料編輯", context: record.product?.barcode ?? "")
            errorMessage = error.localizedDescription
        }
    }
}

private struct CompactNewPurchaseCard: View {
    let product: Product
    let productName: String
    let productBarcode: String
    @Binding var draftPhotos: [Data]
    @Binding var priceText: String
    @Binding var purchaseQuantityText: String
    let onOpenCamera: () -> Void
    let onPhotoData: (Data) -> Void
    let onError: (String) -> Void

    private var existingPhoto: ProductPhoto? { product.sortedPhotos.first }

    private var photoPreview: UIImage? {
        if let existingPhoto {
            return ProductPhotoStore.load(photo: existingPhoto)
        }
        return draftPhotos.first.flatMap(UIImage.init(data:))
    }

    private var historyRecords: [PurchaseRecord] {
        Array(product.comparisonRecords.sorted { $0.recordedAt > $1.recordedAt }.prefix(3))
    }

    var body: some View {
        Section("新購買") {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let photoPreview {
                        Image(uiImage: photoPreview)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("商品條碼", value: ProductIdentifier.isManual(productBarcode) ? "無條碼商品" : productBarcode)
                    LabeledContent("商品名稱", value: productName.isEmpty ? "未命名商品" : productName)
                }
                .font(.subheadline)

                Spacer(minLength: 0)

                PhotoSourceMenu(
                    maximumSelectionCount: 1,
                    onCamera: onOpenCamera,
                    onPhotoData: onPhotoData,
                    onError: onError
                ) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(RaisedGlassIconButtonStyle())
                .accessibilityLabel("更換商品新照片")
            }

            HStack {
                Label("食材庫", systemImage: "cabinet.fill")
                Spacer()
                if let entry = product.currentPantryEntry {
                    Text("在庫")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Text(entry.purchasedAt.formatted(date: .numeric, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未登記")
                        .foregroundStyle(.secondary)
                }
            }

            FastNumericEntryField(
                "購價",
                placeholder: "本次付款總價",
                text: $priceText,
                keyboardType: .decimalPad
            )
            FastNumericEntryField(
                "購數",
                placeholder: "購買數量",
                text: $purchaseQuantityText,
                keyboardType: .numberPad
            )

            if historyRecords.isEmpty {
                LabeledContent("歷次購買價格", value: "尚無紀錄")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("歷次購買價格")
                        .font(.subheadline.bold())
                    ForEach(historyRecords) { record in
                        HStack(spacing: 8) {
                            Text(record.recordedAt.formatted(date: .numeric, time: .omitted))
                            Text(record.storeDisplayName)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(record.formattedPrice)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
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
    @Binding var isGroupPackage: Bool
    @Binding var groupContentCountText: String
    @Binding var isOnSale: Bool
    @Binding var isBuyOneGetOne: Bool
    let storePresets: [StorePreset]
    let showsOverseasFields: Bool
    var prefersCurrentPurchaseFirst = false
    var showsRecordedAt = true
    var showsPriceAndQuantity = true

    var body: some View {
        Section {
            if showsPriceAndQuantity {
                FastNumericEntryField(
                    prefersCurrentPurchaseFirst ? "付款金額" : "付款",
                    placeholder: "本次付款總價",
                    text: $priceText,
                    keyboardType: .decimalPad
                )
                FastNumericEntryField(
                    "購買數量(組)",
                    placeholder: "購買數量",
                    text: $purchaseQuantityText,
                    keyboardType: .numberPad
                )
            }
            storeField
            if showsOverseasFields {
                OverseasTextCaptureButton(title: "從招牌或收據擷取店家") { store = $0 }
            }
            LabeledEntryField("分店", placeholder: "例如：信義店", text: $storeBranch)
            AlignedToggleRow("特價", isOn: $isOnSale)
            AlignedToggleRow("買一送一", isOn: $isBuyOneGetOne)
            PackageToggleRow(isOn: $isGroupPackage) {
                if isGroupPackage {
                    FastNumericTextField(
                        placeholder: "內容物數量",
                        text: $groupContentCountText,
                        keyboardType: .numberPad
                    )
                    .frame(width: 96, height: 34)
                    Text("件")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledEntryField("容量", placeholder: "容量／實際重量（選填）", text: $amountText)
                .keyboardType(.decimalPad)
            unitField
            if showsRecordedAt { recordedAtField }
            if showsOverseasFields {
                Picker("貨幣", selection: $currencyCode) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text(currency.displayName).tag(currency.rawValue)
                    }
                }
            }
        } header: {
            InfoSectionHeader(
                title: "本次採買",
                message: "分店與容量可不填。付款總價會依購買數量換算成每件有效單價；買一送一再以實際取得雙倍件數計算。"
            )
        }
        .font(prefersCurrentPurchaseFirst ? .subheadline : .body)
    }

    private var recordedAtField: some View {
        DatePicker(
            "紀錄時間",
            selection: $recordedAt,
            displayedComponents: [.date, .hourAndMinute]
        )
    }

    private var storeField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("店家")
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            TextField("店家名稱", text: $store)
                .multilineTextAlignment(.leading)
            if !store.isEmpty {
                Button("清除店家", systemImage: "xmark.circle.fill") { store = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
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
                    HistoryMenuLabel()
                }
                .accessibilityLabel("引入歷史店家與分店")
            }
        }
    }

    private var unitField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("單位")
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            TextField("例如：g、ml、包", text: $unit)
                .multilineTextAlignment(.leading)
            if !UnitMemory.recent.isEmpty {
                Menu {
                    ForEach(UnitMemory.recent, id: \.self) { value in
                        Button(value) { unit = value }
                    }
                } label: {
                    HistoryMenuLabel()
                }
                .accessibilityLabel("選擇曾輸入的單位")
            }
        }
    }
}

private struct LabeledEntryField: View {
    let title: String
    let placeholder: String
    let labelWidth: CGFloat
    @Binding var text: String

    init(_ title: String, placeholder: String = "", text: Binding<String>, labelWidth: CGFloat = 72) {
        self.title = title
        self.placeholder = placeholder
        self.labelWidth = labelWidth
        _text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: labelWidth, alignment: .leading)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.leading)
            if !text.isEmpty {
                Button("清除 \(title)", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProductNameField: View {
    @Binding var name: String
    @Binding var brand: String
    @Binding var manufacturerName: String
    let allowsNameEditing: Bool
    let showsOverseasFields: Bool
    var showsMetadataButton = true
    var labelWidth: CGFloat = 72

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("名稱")
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            if allowsNameEditing {
                TextField("商品名稱", text: $name)
                    .multilineTextAlignment(.leading)
                if !name.isEmpty {
                    Button("清除名稱", systemImage: "xmark.circle.fill") { name = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(name.isEmpty ? "未命名商品" : name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsMetadataButton {
                BrandManufacturerButton(
                    brand: $brand,
                    manufacturerName: $manufacturerName,
                    showsOverseasFields: showsOverseasFields
                )
            }
        }
    }
}

private struct BrandManufacturerButton: View {
    @Binding var brand: String
    @Binding var manufacturerName: String
    let showsOverseasFields: Bool
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Text("M")
                .font(.caption.bold())
                .frame(width: 27, height: 27)
                .overlay { Circle().stroke(.primary, lineWidth: 1.5) }
        }
        .buttonStyle(RaisedGlassIconButtonStyle())
        .accessibilityLabel("品牌與廠商選填")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    Section("品牌與廠商（選填）") {
                        LabeledEntryField("品牌", text: $brand)
                        LabeledEntryField("廠商", text: $manufacturerName)
                        if showsOverseasFields {
                            OverseasTextCaptureButton(title: "擷取品牌") { brand = $0 }
                            OverseasTextCaptureButton(title: "擷取廠商") { manufacturerName = $0 }
                        }
                    }
                }
                .navigationTitle("品牌與廠商")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { isPresented = false }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        KeyboardDismissButton()
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct BarcodeFieldRow: View {
    let value: String
    let onCode: (String) -> Void
    let onError: (String) -> Void
    var showsActions = true
    var labelWidth: CGFloat = 72
    @State private var isScannerPresented = false

    var body: some View {
        HStack(spacing: 10) {
            Text("條碼")
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsActions {
                Button {
                    isScannerPresented = true
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .buttonStyle(RaisedGlassIconButtonStyle())
                .accessibilityLabel("開啟相機掃描條碼")
                BarcodePhotoPickerButton(onCode: onCode, onError: onError)
            }
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            BarcodeScannerSheet(onCode: { code in
                onCode(code)
                isScannerPresented = false
            }, onNoBarcode: {
                isScannerPresented = false
            })
        }
    }
}

private struct WishlistBarcodeField: View {
    @Binding var barcode: String
    let isManualProduct: Bool
    let onOpenScanner: () -> Void
    let onCode: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("條碼")
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField("可空白，稍後補登", text: $barcode)
                .font(.body.monospaced())
                .keyboardType(.numberPad)
                .disabled(isManualProduct && ProductIdentifier.isManual(barcode))
                .overlay(alignment: .leading) {
                    if isManualProduct && ProductIdentifier.isManual(barcode) {
                        Text("無條碼商品")
                            .foregroundStyle(.secondary)
                    }
                }
            Button("拍照掃描條碼", systemImage: "camera.viewfinder", action: onOpenScanner)
                .labelStyle(.iconOnly)
                .buttonStyle(RaisedGlassIconButtonStyle())
                .accessibilityLabel("拍照掃描條碼")
            BarcodePhotoPickerButton(onCode: onCode, onError: onError)
        }
    }
}

private struct WishlistStoreField: View {
    @Binding var store: String
    @Binding var storeBranch: String
    let storePresets: [StorePreset]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("店家")
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("店家名稱（選填）", text: $store)
                    .multilineTextAlignment(.leading)
                if !store.isEmpty {
                    Button("清除店家", systemImage: "xmark.circle.fill") { store = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                if !storePresets.isEmpty {
                    Menu {
                        ForEach(Array(storePresets.prefix(12))) { preset in
                            Button(preset.displayName) {
                                store = preset.name
                                storeBranch = preset.branch
                            }
                        }
                    } label: {
                        HistoryMenuLabel()
                    }
                    .accessibilityLabel("選擇歷史店家與分店")
                }
            }
            LabeledEntryField("分店", placeholder: "分店（選填）", text: $storeBranch, labelWidth: 64)
        }
    }
}

private struct BarcodePhotoPickerButton: View {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    @State private var selectedItem: PhotosPickerItem?
    @State private var isReading = false

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Group {
                if isReading {
                    ProgressView()
                } else {
                    Image(systemName: "photo.badge.magnifyingglass")
                }
            }
            .font(.headline)
        }
        .buttonStyle(RaisedGlassIconButtonStyle())
        .disabled(isReading)
        .accessibilityLabel("從相簿照片辨識條碼")
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await readBarcode(from: item) }
        }
    }

    @MainActor
    private func readBarcode(from item: PhotosPickerItem) async {
        isReading = true
        defer {
            isReading = false
            selectedItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw BarcodePhotoRecognitionError.invalidImage
            }
            onCode(try await BarcodePhotoRecognizer.recognize(data))
        } catch {
            AppErrorLogger.record(error, category: "條碼辨識", context: "從相簿照片讀取")
            onError(error.localizedDescription)
        }
    }
}

struct KeyboardDismissButton: View {
    var body: some View {
        Button("隱藏鍵盤", systemImage: "keyboard.chevron.compact.down") {
            hideKeyboard()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(RaisedGlassIconButtonStyle())
        .accessibilityLabel("隱藏鍵盤")
    }
}

private struct HistoryMenuLabel: View {
    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.headline)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
    }
}

private struct PackageToggleRow<Accessory: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let accessory: () -> Accessory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("一組包裝")
                        .frame(width: 88, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isOn ? AppTheme.accent.opacity(0.72) : Color.secondary.opacity(0.14))
                        Circle()
                            .fill(.background)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                            .padding(3)
                            .offset(x: isOn ? 24 : 0)
                    }
                    .frame(width: 54, height: 30)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("一組包裝")
            .accessibilityValue(isOn ? "開啟" : "關閉")
            Spacer(minLength: 4)
            accessory()
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            isOn.toggle()
        }
    }
}

private struct AlignedToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let accessory: AnyView?

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
        accessory = nil
    }

    init<Accessory: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        _isOn = isOn
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 112, alignment: .leading)
            Toggle("", isOn: $isOn)
                .labelsHidden()
            Spacer(minLength: 4)
            accessory
        }
    }
}

private struct FastNumericEntryField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let labelWidth: CGFloat

    init(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        labelWidth: CGFloat = 112
    ) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.keyboardType = keyboardType
        self.labelWidth = labelWidth
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: labelWidth, alignment: .leading)
            FastNumericTextField(
                placeholder: placeholder,
                text: $text,
                keyboardType: keyboardType
            )
            .frame(minHeight: 34)
            if !text.isEmpty {
                Button("清除 \(title)", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FastNumericTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: FastNumericTextField
        weak var textField: UITextField?

        init(_ parent: FastNumericTextField) { self.parent = parent }

        @objc func changed(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectedTextRange = textField.textRange(
                    from: textField.endOfDocument,
                    to: textField.endOfDocument
                )
            }
        }

        func makeKeyboardAccessory() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexible = UIBarButtonItem(systemItem: .flexibleSpace)
            let dismiss = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain,
                target: self,
                action: #selector(dismissKeyboard)
            )
            dismiss.accessibilityLabel = "隱藏鍵盤"
            toolbar.items = [flexible, dismiss]
            return toolbar
        }

        @objc private func dismissKeyboard() {
            textField?.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.textAlignment = .left
        field.clearButtonMode = .never
        field.delegate = context.coordinator
        context.coordinator.textField = field
        field.inputAccessoryView = context.coordinator.makeKeyboardAccessory()
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.keyboardType = keyboardType
    }
}

enum UnitMemory {
    private static let key = "SnapsShopList.rememberedUnits"

    static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? ["g", "ml", "包", "盒"]
    }

    static func remember(_ value: String) {
        let normalized = value.trimmed
        guard !normalized.isEmpty else { return }
        var values = recent.filter { $0.localizedCaseInsensitiveCompare(normalized) != .orderedSame }
        values.insert(normalized, at: 0)
        UserDefaults.standard.set(Array(values.prefix(12)), forKey: key)
    }
}

private struct GPSLocationSection: View {
    @ObservedObject var recorder: LocationRecorder
    @Binding var city: String
    @Binding var district: String
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
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
                LabeledEntryField("縣市", placeholder: "例如：台北市", text: $city)
                LabeledEntryField("區域", placeholder: "例如：信義區", text: $district)
                Button("重新取得定位", systemImage: "location.circle") {
                    recorder.requestLocation()
                }
                .disabled(recorder.isLocating)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        recorder.location == nil ? recorder.statusText : "GPS 已取得",
                        systemImage: recorder.location == nil ? "location.slash" : "location.fill"
                    )
                    .foregroundStyle(recorder.location == nil ? .secondary : AppTheme.accent)
                    Text(regionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("GPS 紀錄")
        }
    }

    private var regionSummary: String {
        let value = [city, district].filter { !$0.isEmpty }.joined(separator: " ")
        return value.isEmpty ? "縣市與區域尚未取得" : value
    }
}

private struct ExistingGPSSection: View {
    let record: PurchaseRecord
    @Binding var city: String
    @Binding var district: String
    @State private var isExpanded = false

    var body: some View {
        Section("GPS 紀錄") {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let latitude = record.latitude, let longitude = record.longitude {
                    LabeledContent("座標", value: String(format: "%.6f, %.6f", latitude, longitude))
                        .font(.caption)
                }
                LabeledEntryField("縣市", placeholder: "例如：台北市", text: $city)
                LabeledEntryField("區域", placeholder: "例如：信義區", text: $district)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        record.latitude == nil ? "GPS 未取得" : "GPS 已取得",
                        systemImage: record.latitude == nil ? "location.slash" : "location.fill"
                    )
                    .foregroundStyle(record.latitude == nil ? .secondary : AppTheme.accent)
                    Text(regionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var regionSummary: String {
        let value = [city, district].filter { !$0.isEmpty }.joined(separator: " ")
        return value.isEmpty ? "縣市與區域尚未取得" : value
    }
}

private struct EditablePurchasePhotosSection: View {
    let existingPhotos: [ProductPhoto]
    @Binding var newImages: [Data]
    let onAdd: () -> Void
    let onReplace: (ProductPhoto) -> Void
    let onDelete: (ProductPhoto) -> Void
    let onError: (String) -> Void

    private var availableCount: Int {
        max(0, AppLimits.maximumPhotos - existingPhotos.count - newImages.count)
    }

    private var displayedAddSlots: Int {
        existingPhotos.isEmpty && newImages.isEmpty ? min(1, availableCount) : availableCount
    }

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(existingPhotos) { photo in
                        existingPhoto(photo)
                    }
                    ForEach(Array(newImages.enumerated()), id: \.offset) { index, data in
                        newPhoto(data, index: index)
                    }
                    ForEach(0..<displayedAddSlots, id: \.self) { _ in
                        addSlot
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)

        } header: {
            Text("商品照片")
        }
    }

    private var addSlot: some View {
        PhotoSourceMenu(
            maximumSelectionCount: availableCount,
            onCamera: onAdd,
            onPhotoData: { data in
                guard existingPhotos.count + newImages.count < AppLimits.maximumPhotos else { return }
                newImages.append(data)
            },
            onError: onError
        ) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.08))
                Image(systemName: existingPhotos.isEmpty && newImages.isEmpty ? "camera.fill" : "plus.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                Image(systemName: "photo.on.rectangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                    .padding(9)
            }
            .frame(width: 124, height: 124)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("拍照或從相簿選取商品照片，尚可 \(availableCount) 張")
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
    var title: String? = "商品照片"
    var existingPhotoCount = 0
    @Binding var images: [Data]
    var onError: (String) -> Void = { _ in }
    let onOpenCamera: () -> Void

    private var availableCount: Int {
        max(0, AppLimits.maximumPhotos - existingPhotoCount - images.count)
    }

    private var displayedAddSlots: Int {
        images.isEmpty ? min(1, availableCount) : availableCount
    }

    var body: some View {
        Section {
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
                    ForEach(0..<displayedAddSlots, id: \.self) { _ in
                        PhotoSourceMenu(
                            maximumSelectionCount: availableCount,
                            onCamera: onOpenCamera,
                            onPhotoData: { data in
                                guard existingPhotoCount + images.count < AppLimits.maximumPhotos else { return }
                                images.append(data)
                            },
                            onError: onError
                        ) {
                            ZStack(alignment: .bottomTrailing) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.blue.opacity(0.08))
                                Image(systemName: images.isEmpty ? "camera.fill" : "plus.circle.fill")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                Image(systemName: "photo.on.rectangle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                    .padding(9)
                            }
                            .frame(width: 112, height: 112)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("拍照或從相簿選取商品照片，尚可 \(availableCount) 張")
                    }
                }
            }
            .scrollIndicators(.visible)

            if !images.isEmpty {
                Label("左右滑動可查看並加入其他照片", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            if let title {
                Text(title)
            }
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
            LeadingInfoRow("比較貨幣", SupportedCurrency.normalized(statistics.currencyCode).displayName)
            LeadingInfoRow("最低單價", currency(statistics.lowestRecord.effectiveUnitPrice, code: statistics.currencyCode))
            LeadingInfoRow("最低店家", statistics.lowestRecord.storeDisplayName)
            LeadingInfoRow("最低時間", statistics.lowestRecord.recordedAt.formatted(date: .numeric, time: .shortened))
            LeadingInfoRow("平均單價", currency(statistics.averageEffectivePrice, code: statistics.currencyCode))
            LeadingInfoRow("最高單價", currency(statistics.highestRecord.effectiveUnitPrice, code: statistics.currencyCode))
            LeadingInfoRow("最高店家", statistics.highestRecord.storeDisplayName)
            LeadingInfoRow("最高時間", statistics.highestRecord.recordedAt.formatted(date: .numeric, time: .shortened))

            if let reference = statistics.latestRecord.referenceUnitPrice {
                LeadingInfoRow("最新單價", "\(reference.label) \(currency(reference.value, code: statistics.currencyCode))")
            }

            if let lowestNormalized = statistics.lowestNormalizedRecord,
               let reference = lowestNormalized.referenceUnitPrice {
                LeadingInfoRow("最低換算", "\(reference.label) \(currency(reference.value, code: statistics.currencyCode))")
            }

            HStack {
                Text("換算說明")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                InfoTipButton(
                    title: "價格記憶助手",
                    message: "價格統計只比較相同貨幣。有效單價會依購買數量換算；買一送一再以實際取得雙倍數量計算。"
                )
            }
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

func rememberStore(
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
