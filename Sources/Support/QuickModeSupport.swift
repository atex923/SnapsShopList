import CoreLocation
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

final class QuickModeSession: ObservableObject {
    @Published var isEnabled = false
}

struct QuickDraftPhotoReference: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let source: String
}

struct QuickDraft: Codable, Identifiable, Equatable {
    var id: UUID
    var productID: UUID?
    var barcode: String
    var priceText: String
    var quantityText: String
    var amountText: String
    var unit: String
    var isOnSale: Bool
    var isBuyOneGetOne: Bool
    var name: String
    var store: String
    var recordedAt: Date
    var city: String
    var district: String
    var latitude: Double?
    var longitude: Double?
    var locationAccuracy: Double?
    var locationSource: PurchaseLocationSource
    var currencyCode: String
    var photos: [QuickDraftPhotoReference]
    var updatedAt: Date

    var barcodeDisplayText: String {
        ProductIdentifier.isManual(barcode) ? "無條碼商品" : barcode
    }

    var formattedPrice: String {
        guard let price = LocalizedNumberParser.double(from: priceText) else { return "尚未填價" }
        return SupportedCurrency.format(price, code: currencyCode)
    }
}

struct QuickDraftPhotoItem: Identifiable {
    let id: UUID
    var data: Data
    var createdAt: Date
    var source: String
    var fileName: String?
}

struct QuickEntryRequest: Identifiable {
    let id = UUID()
    let barcode: String
    let product: Product?
    let draft: QuickDraft?
    let opensCameraImmediately: Bool
}

struct QuickFullEntryRequest: Identifiable {
    let id = UUID()
    let barcode: String
    let product: Product?
    let draft: QuickDraft?
}

struct QuickEntryResult {
    let product: Product?
    let draft: QuickDraft?
    let completed: Bool
}

enum QuickDraftStore {
    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SnapsShopListQuickDrafts", isDirectory: true)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func save(_ draft: QuickDraft, photoItems: [QuickDraftPhotoItem]) async throws -> QuickDraft {
        let fileManager = FileManager.default
        let folder = rootURL.appendingPathComponent(draft.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var references: [QuickDraftPhotoReference] = []

        for item in photoItems.sorted(by: { $0.createdAt < $1.createdAt }) {
            let fileName = item.fileName ?? "\(item.id.uuidString).jpg"
            let url = folder.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: url.path) {
                let data = try await ProductPhotoStore.optimizedJPEG(from: item.data)
                try data.write(to: url, options: .atomic)
            }
            references.append(.init(id: item.id, fileName: fileName, createdAt: item.createdAt, source: item.source))
        }

        let referencedNames = Set(references.map(\.fileName))
        let existingFiles = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in existingFiles where url.pathExtension.lowercased() == "jpg" && !referencedNames.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }

        var stored = draft
        stored.photos = references
        stored.updatedAt = .now
        try encoder.encode(stored).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        return stored
    }

    static func photoItems(for draft: QuickDraft) -> [QuickDraftPhotoItem] {
        let folder = rootURL.appendingPathComponent(draft.id.uuidString, isDirectory: true)
        return draft.photos.compactMap { reference in
            let url = folder.appendingPathComponent(reference.fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return .init(
                id: reference.id,
                data: data,
                createdAt: reference.createdAt,
                source: reference.source,
                fileName: reference.fileName
            )
        }
    }

    static func latestDraft() -> QuickDraft? {
        allDrafts().max { $0.updatedAt < $1.updatedAt }
    }

    static func allDrafts() -> [QuickDraft] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")) else { return nil }
            return try? decoder.decode(QuickDraft.self, from: data)
        }
    }

    static func delete(_ draft: QuickDraft) {
        let folder = rootURL.appendingPathComponent(draft.id.uuidString, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch {
            AppErrorLogger.record(error, category: "快速草稿", context: "刪除 \(draft.id)")
        }
    }

    static func cleanupExpiredDrafts(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        for draft in allDrafts() where draft.updatedAt < cutoff { delete(draft) }
    }
}

enum PhotoLocationMetadata {
    static func coordinate(from data: Data) -> CLLocationCoordinate2D? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
        return .init(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
    }
}

struct QuickEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePreset.lastUsedAt, order: .reverse) private var storePresets: [StorePreset]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage(OverseasModeSettings.currencyKey) private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue

    let request: QuickEntryRequest
    let onSaved: (QuickEntryResult) -> Void

    @State private var draftID: UUID
    @State private var barcode: String
    @State private var name: String
    @State private var store: String
    @State private var priceText: String
    @State private var quantityText: String
    @State private var amountText: String
    @State private var unit: String
    @State private var isOnSale: Bool
    @State private var isBuyOneGetOne: Bool
    @State private var recordedAt: Date
    @State private var city: String
    @State private var district: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationAccuracy: Double?
    @State private var locationSource: PurchaseLocationSource
    @State private var photos: [QuickDraftPhotoItem]
    @State private var selectedPhotoIDs: Set<UUID>
    @State private var selectedLibraryItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var didAttemptAutomaticCamera = false
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showsDeleteConfirmation = false
    @StateObject private var locationRecorder = LocationRecorder()

    init(request: QuickEntryRequest, onSaved: @escaping (QuickEntryResult) -> Void) {
        self.request = request
        self.onSaved = onSaved
        let draft = request.draft
        let latest = request.product?.latestRecord
        let loadedPhotos = draft.map(QuickDraftStore.photoItems) ?? []
        let inheritedAmount = latest?.amount ?? 0
        _draftID = State(initialValue: draft?.id ?? UUID())
        _barcode = State(initialValue: draft?.barcode ?? request.barcode)
        _name = State(initialValue: draft?.name ?? request.product?.name ?? "")
        _store = State(initialValue: draft?.store ?? "")
        _priceText = State(initialValue: draft?.priceText ?? "")
        _quantityText = State(initialValue: draft?.quantityText ?? "")
        _amountText = State(initialValue: draft?.amountText ?? (inheritedAmount > 0
            ? inheritedAmount.formatted(.number.precision(.fractionLength(0...2)))
            : ""))
        _unit = State(initialValue: draft?.unit ?? latest?.unit ?? "")
        _isOnSale = State(initialValue: draft?.isOnSale ?? false)
        _isBuyOneGetOne = State(initialValue: draft?.isBuyOneGetOne ?? false)
        _recordedAt = State(initialValue: draft?.recordedAt ?? .now)
        _city = State(initialValue: draft?.city ?? "")
        _district = State(initialValue: draft?.district ?? "")
        _latitude = State(initialValue: draft?.latitude)
        _longitude = State(initialValue: draft?.longitude)
        _locationAccuracy = State(initialValue: draft?.locationAccuracy)
        _locationSource = State(initialValue: draft?.locationSource ?? .none)
        _photos = State(initialValue: loadedPhotos)
        _selectedPhotoIDs = State(initialValue: Set(loadedPhotos.prefix(AppLimits.maximumPhotos).map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BarcodeFieldRow(
                        value: ProductIdentifier.isManual(barcode) ? "無條碼商品" : barcode,
                        onCode: { barcode = $0 },
                        onError: { errorMessage = $0 }
                    )
                }

                quickPhotosSection

                Section {
                    QuickCompactField("價格（必要）", text: $priceText, keyboard: .decimalPad)
                    QuickCompactField("數量（選填）", text: $quantityText, keyboard: .numberPad)
                    QuickCompactField("容量（選填）", text: $amountText, keyboard: .decimalPad)
                    QuickCompactField("單位（選填）", text: $unit)
                    Toggle("特價", isOn: $isOnSale)
                    Toggle("買一送一", isOn: $isBuyOneGetOne)
                    QuickCompactField("商品名稱（選填）", text: $name)
                    if overseasModeEnabled {
                        OverseasTextCaptureButton(title: "從相機或相簿擷取商品名稱") { name = $0 }
                    }
                    QuickCompactField("店家（選填）", text: $store)
                    if overseasModeEnabled {
                        OverseasTextCaptureButton(title: "從相機或相簿擷取店家名稱") { store = $0 }
                    }
                    DatePicker("紀錄時間", selection: $recordedAt)
                }

                Section {
                    if let latitude, let longitude {
                        Label("GPS 已取得", systemImage: "location.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(String(format: "%.5f, %.5f", latitude, longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Label("GPS 未取得，仍可暫存", systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
            .navigationTitle("快速紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if request.draft != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("刪除草稿", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("暫存", systemImage: "tray.and.arrow.down.fill") {
                        Task { await saveDraft() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasValidPrice || isSubmitting)

                    Button("正式儲存", systemImage: "checkmark.circle.fill") {
                        Task { await saveFormalRecord() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(!canSaveFormally || isSubmitting)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data, source in
                addPhoto(data, source: source == .camera ? "camera" : "library")
                if source == .camera { ProductPhotoStore.saveToPhotoLibrary(data) }
                isCameraPresented = false
            }, onCancel: { isCameraPresented = false })
            .ignoresSafeArea()
        }
        .alert("快速紀錄", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) { Button("好", role: .cancel) {} } message: { Text(errorMessage) }
        .confirmationDialog("刪除這份快速草稿？", isPresented: $showsDeleteConfirmation) {
            Button("刪除草稿及暫存照片", role: .destructive) { deleteDraft() }
            Button("取消", role: .cancel) {}
        }
        .task {
            locationRecorder.requestLocation()
            if request.opensCameraImmediately && !didAttemptAutomaticCamera {
                didAttemptAutomaticCamera = true
                openCamera()
            }
        }
        .onChange(of: locationRecorder.location) { _, location in
            guard let location else { return }
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            locationAccuracy = location.horizontalAccuracy
            locationSource = .liveGPS
        }
        .onChange(of: locationRecorder.suggestedCity) { _, value in if !value.isEmpty { city = value } }
        .onChange(of: locationRecorder.suggestedDistrict) { _, value in if !value.isEmpty { district = value } }
    }

    private var quickPhotosSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photos.sorted(by: { $0.createdAt < $1.createdAt })) { photo in
                        ZStack(alignment: .topTrailing) {
                            if let image = UIImage(data: photo.data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selectedPhotoIDs.contains(photo.id) ? Color.blue : .clear, lineWidth: 4)
                                    }
                                    .onTapGesture { toggleSelection(photo.id) }
                            }
                            Button {
                                photos.removeAll { $0.id == photo.id }
                                selectedPhotoIDs.remove(photo.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                            }
                            .padding(5)
                        }
                        .overlay(alignment: .bottomLeading) {
                            Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedPhotoIDs.contains(photo.id) ? .blue : .white)
                                .padding(6)
                        }
                    }

                    if photos.count < AppLimits.maximumQuickDraftPhotos {
                        Button { openCamera() } label: {
                            Image(systemName: "camera.fill")
                                .font(.title)
                                .frame(width: 72, height: 104)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("快速拍照")

                        PhotosPicker(
                            selection: $selectedLibraryItems,
                            maxSelectionCount: AppLimits.maximumQuickDraftPhotos - photos.count,
                            matching: .images
                        ) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title)
                                .frame(width: 72, height: 104)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("從相簿加入照片")
                        .onChange(of: selectedLibraryItems) { _, items in
                            Task { await importLibraryPhotos(items) }
                        }
                    }
                }
            }
            Text("暫存最多10張；藍框為正式儲存照片，最多選5張（目前 \(selectedPhotoIDs.count) 張）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hasValidPrice: Bool {
        guard let price = LocalizedNumberParser.double(from: priceText) else { return false }
        return price >= 0 && price.isFinite
    }

    private var canSaveFormally: Bool {
        hasValidPrice && !name.trimmed.isEmpty && selectedPhotoIDs.count <= AppLimits.maximumPhotos
    }

    private func currentDraft() -> QuickDraft {
        QuickDraft(
            id: draftID,
            productID: request.product?.id,
            barcode: barcode,
            priceText: priceText,
            quantityText: quantityText,
            amountText: amountText,
            unit: unit,
            isOnSale: isOnSale,
            isBuyOneGetOne: isBuyOneGetOne,
            name: name,
            store: store,
            recordedAt: recordedAt,
            city: city,
            district: district,
            latitude: latitude,
            longitude: longitude,
            locationAccuracy: locationAccuracy,
            locationSource: locationSource,
            currencyCode: PurchaseCurrencyPolicy.activeCode(
                overseasModeEnabled: overseasModeEnabled,
                preferredCode: defaultCurrencyCode
            ),
            photos: request.draft?.photos ?? [],
            updatedAt: .now
        )
    }

    @MainActor
    private func saveDraft() async {
        guard hasValidPrice, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let stored = try await QuickDraftStore.save(currentDraft(), photoItems: photos)
            onSaved(.init(product: request.product, draft: stored, completed: false))
            dismiss()
        } catch {
            AppErrorLogger.record(error, category: "快速草稿", context: barcode)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveFormalRecord() async {
        guard canSaveFormally, !isSubmitting else { return }
        guard let price = LocalizedNumberParser.double(from: priceText) else { return }
        let quantityWasEntered = !quantityText.trimmed.isEmpty
        guard !quantityWasEntered || LocalizedNumberParser.positiveInteger(from: quantityText) != nil else {
            errorMessage = "購買數量必須是大於0的整數，或保持空白。"
            return
        }
        let amount: Double
        if amountText.trimmed.isEmpty {
            amount = 0
        } else if let value = LocalizedNumberParser.double(from: amountText), value > 0 {
            amount = value
        } else {
            errorMessage = "容量必須大於0，或保持空白。"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let product = try findOrCreateProduct()
            let complete = !store.trimmed.isEmpty && !unit.trimmed.isEmpty && quantityWasEntered
            let record = PurchaseRecord(
                recordedAt: recordedAt,
                store: store.trimmed,
                city: city.trimmed,
                district: district.trimmed,
                price: price,
                currencyCode: PurchaseCurrencyPolicy.activeCode(
                    overseasModeEnabled: overseasModeEnabled,
                    preferredCode: defaultCurrencyCode
                ),
                amount: amount,
                unit: unit.trimmed,
                isOnSale: isOnSale,
                isBuyOneGetOne: isBuyOneGetOne,
                isDraft: false,
                purchaseQuantity: quantityWasEntered ? (LocalizedNumberParser.positiveInteger(from: quantityText) ?? 1) : 1,
                latitude: latitude,
                longitude: longitude,
                locationAccuracy: locationAccuracy,
                product: product,
                recordStatus: complete ? .complete : .comparison,
                quantityWasEntered: quantityWasEntered,
                locationSource: locationSource
            )
            modelContext.insert(record)
            if !store.trimmed.isEmpty {
                try rememberStore(name: store, branch: "", city: city, district: district, usedAt: recordedAt, in: modelContext)
            }
            UnitMemory.remember(unit)

            let selected = photos
                .filter { selectedPhotoIDs.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(AppLimits.maximumPhotos)
            for photo in selected {
                let optimized = try await ProductPhotoStore.optimizedJPEG(from: photo.data)
                modelContext.insert(ProductPhoto(fileName: "", imageData: optimized, createdAt: photo.createdAt, product: product))
            }
            try modelContext.save()
            let draft = currentDraft()
            QuickDraftStore.delete(draft)
            onSaved(.init(product: product, draft: nil, completed: true))
            dismiss()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "快速正式儲存", context: barcode)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func findOrCreateProduct() throws -> Product {
        if let product = request.product {
            if !name.trimmed.isEmpty { product.name = name.trimmed }
            return product
        }
        let searchedBarcode = barcode
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { $0.barcode == searchedBarcode })
        descriptor.fetchLimit = 1
        if let product = try modelContext.fetch(descriptor).first {
            if product.name.isEmpty { product.name = name.trimmed }
            return product
        }
        let product = Product(barcode: barcode, name: name.trimmed)
        modelContext.insert(product)
        return product
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            errorMessage = "模擬器沒有相機；請改用相簿或稍後在 iPhone 測試。"
            return
        }
        isCameraPresented = true
    }

    private func addPhoto(_ data: Data, source: String) {
        guard photos.count < AppLimits.maximumQuickDraftPhotos else { return }
        let item = QuickDraftPhotoItem(id: UUID(), data: data, createdAt: .now, source: source, fileName: nil)
        photos.append(item)
        if selectedPhotoIDs.count < AppLimits.maximumPhotos { selectedPhotoIDs.insert(item.id) }
        if latitude == nil, let coordinate = PhotoLocationMetadata.coordinate(from: data) {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            locationSource = .photoMetadata
        }
    }

    @MainActor
    private func importLibraryPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedLibraryItems = [] }
        for item in items where photos.count < AppLimits.maximumQuickDraftPhotos {
            do {
                if let data = try await item.loadTransferable(type: Data.self) { addPhoto(data, source: "photoLibrary") }
            } catch {
                AppErrorLogger.record(error, category: "快速相簿", context: barcode)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else if selectedPhotoIDs.count < AppLimits.maximumPhotos {
            selectedPhotoIDs.insert(id)
        } else {
            errorMessage = "正式商品照片最多選5張。"
        }
    }

    private func deleteDraft() {
        let draft = request.draft ?? currentDraft()
        QuickDraftStore.delete(draft)
        onSaved(.init(product: request.product, draft: nil, completed: false))
        dismiss()
    }
}

private struct QuickCompactField: View {
    let prompt: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    init(_ prompt: String, text: Binding<String>, keyboard: UIKeyboardType = .default) {
        self.prompt = prompt
        _text = text
        self.keyboard = keyboard
    }

    var body: some View {
        HStack {
            TextField(prompt, text: $text)
                .keyboardType(keyboard)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除\(prompt)")
            }
        }
    }
}
