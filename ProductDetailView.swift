import SwiftData
import SwiftUI

struct ScannedProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allProducts: [Product]
    @Bindable var product: Product
    let onSaved: () -> Void

    @State private var photoIndex = 0
    @State private var isCameraPresented = false
    @State private var isPurchasePresented = false
    @State private var photoPendingDeletion: ProductPhoto?
    @State private var photoBeingReplaced: ProductPhoto?
    @State private var alertMessage = ""

    private var photos: [ProductPhoto] { product.sortedPhotos }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    scannedPhotoSection
                    ProductIdentityCard(product: product)
                    priceTable
                    scannedPantrySection
                    RelatedProductsSection(product: product, allProducts: allProducts)

                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        Label("進入採買記事商品資料", systemImage: "book.pages")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("新增商品資料", systemImage: "plus.circle.fill") {
                        isPurchasePresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .appModeBackground()
            .navigationTitle(product.name.isEmpty ? "商品資料" : product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isPurchasePresented) {
            NewPurchaseView(product: product) { onSaved() }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data, source in
                isCameraPresented = false
                let replacedPhoto = photoBeingReplaced
                photoBeingReplaced = nil
                Task { await savePhoto(data, replacing: replacedPhoto, saveToLibrary: source == .camera) }
            }, onCancel: {
                photoBeingReplaced = nil
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .onChange(of: photos.count) { _, newCount in
            photoIndex = min(photoIndex, max(0, newCount - 1))
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
            Text("照片會從購物記本的商品資料中刪除，此動作無法復原。")
        }
        .alert("操作失敗", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var scannedPhotoSection: some View {
        VStack(spacing: 8) {
            Group {
                if photos.isEmpty {
                    PhotoSourceMenu(
                        maximumSelectionCount: AppLimits.maximumPhotos,
                        onCamera: {
                            photoBeingReplaced = nil
                            openCamera()
                        },
                        onPhotoData: { data in
                            Task { await savePhoto(data, replacing: nil, saveToLibrary: false) }
                        },
                        onError: { alertMessage = $0 }
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 58))
                            Text("拍照或從相簿選取")
                                .font(.headline)
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 270)
                        .background(.background)
                    }
                    .buttonStyle(ImmediatePressStyle())
                } else if let image = image(at: photoIndex) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                } else {
                    ContentUnavailableView("照片正在同步", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 270)
                        .background(.background)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.quaternary, lineWidth: 1)
            }

            if !photos.isEmpty {
                HStack {
                    Button {
                        if photos.indices.contains(photoIndex) {
                            photoPendingDeletion = photos[photoIndex]
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .accessibilityLabel("刪除目前照片")

                    Spacer()

                    if photos.count > 1 {
                        HStack(spacing: 18) {
                            Button("上一張", systemImage: "chevron.left") {
                                photoIndex = max(0, photoIndex - 1)
                            }
                            .disabled(photoIndex == 0)

                            Text("\(photoIndex + 1) / \(photos.count)")
                                .font(.caption.bold())

                            Button("下一張", systemImage: "chevron.right") {
                                photoIndex = min(photos.count - 1, photoIndex + 1)
                            }
                            .disabled(photoIndex >= photos.count - 1)
                        }
                        .labelStyle(.iconOnly)
                    }

                    Spacer()

                    PhotoSourceMenu(
                        maximumSelectionCount: 1,
                        onCamera: {
                            photoBeingReplaced = photos[photoIndex]
                            openCamera()
                        },
                        onPhotoData: { data in
                            guard photos.indices.contains(photoIndex) else { return }
                            Task { await savePhoto(data, replacing: photos[photoIndex], saveToLibrary: false) }
                        },
                        onError: { alertMessage = $0 }
                    ) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityLabel("更換目前照片")
                }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 4)
            }
        }
    }

    private var priceTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歷次價格")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("紀錄時間")
                    Text("店家")
                    Text("價格").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)

                Divider().gridCellColumns(3)

                ForEach(product.comparisonRecords.sorted { $0.recordedAt > $1.recordedAt }) { record in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(record.recordedAt.formatted(date: .numeric, time: .shortened))
                        Text(record.storeDisplayName)
                            .lineLimit(2)
                        Text(record.formattedPrice)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var scannedPantrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("食材庫", systemImage: "cabinet.fill")
                    .font(.title3.bold())
                Spacer()
                if product.currentPantryEntry != nil {
                    Text("在庫")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
            }

            if let entry = product.currentPantryEntry {
                LabeledContent(
                    "購入時間",
                    value: PantryDateFormatter.string(from: entry.purchasedAt)
                )
                .font(.caption)
                HStack {
                    Text("保存期限")
                    Spacer()
                    Text(PantryDateFormatter.string(from: entry.expirationDate))
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
                .font(.caption)
            } else {
                Text("目前未在庫")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func image(at index: Int) -> UIImage? {
        guard photos.indices.contains(index) else { return nil }
        return ProductPhotoStore.load(photo: photos[index])
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            alertMessage = "這台裝置沒有可用的相機，請改用 iPhone 實機測試。"
            return
        }
        isCameraPresented = true
    }

    @MainActor
    private func savePhoto(
        _ sourceData: Data,
        replacing photo: ProductPhoto?,
        saveToLibrary: Bool = true
    ) async {
        do {
            let imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            if let photo {
                let legacyFileName = photo.fileName
                photo.imageData = imageData
                photo.fileName = ""
                photo.createdAt = .now
                try modelContext.save()
                ProductPhotoStore.delete(fileName: legacyFileName)
            } else {
                let newPhoto = ProductPhoto(fileName: "", imageData: imageData, product: product)
                modelContext.insert(newPhoto)
                try modelContext.save()
            }
            if saveToLibrary {
                ProductPhotoStore.saveToPhotoLibrary(sourceData) { result in
                    if case .failure(let error) = result { alertMessage = error.localizedDescription }
                }
            }
            photoIndex = 0
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片儲存", context: product.barcode)
            alertMessage = error.localizedDescription
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
            alertMessage = error.localizedDescription
        }
    }
}

struct ProductDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allProducts: [Product]
    @Bindable var product: Product
    @State private var photoIndex = 0
    @State private var isCameraPresented = false
    @State private var isGalleryPresented = false
    @State private var alertMessage = ""
    @State private var recordPendingDeletion: PurchaseRecord?
    @State private var recordBeingEdited: PurchaseRecord?
    @State private var recordSort: PurchaseRecordSort = .timeNewest
    @State private var isPriceMemoryExpanded = false

    private var photos: [ProductPhoto] { product.sortedPhotos }
    private var displayedRecords: [PurchaseRecord] {
        switch recordSort {
        case .timeNewest:
            product.sortedRecords.filter { $0.recordStatus != .wishlistQuote }
        case .priceLowest:
            (product.records ?? []).filter { $0.recordStatus != .wishlistQuote }.sorted {
                if $0.normalizedCurrencyCode != $1.normalizedCurrencyCode {
                    return $0.normalizedCurrencyCode < $1.normalizedCurrencyCode
                }
                if $0.quantityWasEntered != $1.quantityWasEntered {
                    return $0.quantityWasEntered && !$1.quantityWasEntered
                }
                if $0.effectiveUnitPrice == $1.effectiveUnitPrice {
                    return $0.recordedAt > $1.recordedAt
                }
                return $0.effectiveUnitPrice < $1.effectiveUnitPrice
            }
        case .store:
            (product.records ?? []).filter { $0.recordStatus != .wishlistQuote }.sorted {
                let comparison = $0.storeDisplayName.localizedStandardCompare($1.storeDisplayName)
                return comparison == .orderedSame
                    ? $0.recordedAt > $1.recordedAt
                    : comparison == .orderedAscending
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                photoSection
                ProductIdentityCard(product: product)
                recordsSection
                comparisonRecordsSection
                    RelatedProductsSection(product: product, allProducts: allProducts)
                    priceMemorySection
                    PantryHistorySection(product: product)
                    if isOverseasOnlyProduct {
                        taiwanPantryAction
                    }
                }
            .padding()
        }
        .appModeBackground()
        .navigationTitle(product.name.isEmpty ? "商品資料" : product.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data, source in
                isCameraPresented = false
                Task { await addPhoto(data, saveToLibrary: source == .camera) }
            }, onCancel: {
                isCameraPresented = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isGalleryPresented) {
            PhotoGalleryView(product: product)
        }
        .sheet(item: $recordBeingEdited) { record in
            EditPurchaseView(record: record)
        }
        .onChange(of: photos.count) { _, newCount in
            photoIndex = min(photoIndex, max(0, newCount - 1))
        }
        .alert("操作失敗", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "刪除這筆採買紀錄？",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { if !$0 { recordPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除紀錄", role: .destructive) {
                if let record = recordPendingDeletion { deleteRecord(record) }
            }
            Button("取消", role: .cancel) { recordPendingDeletion = nil }
        }
    }

    private var photoSection: some View {
        VStack(spacing: 8) {
            Group {
                if photos.isEmpty {
                    PhotoSourceMenu(
                        maximumSelectionCount: AppLimits.maximumPhotos,
                        onCamera: { openCamera() },
                        onPhotoData: { data in
                            Task { await addPhoto(data, saveToLibrary: false) }
                        },
                        onError: { alertMessage = $0 }
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 58))
                            Text("拍照或從相簿選取")
                                .font(.headline)
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 270)
                        .background(.background)
                    }
                    .buttonStyle(ImmediatePressStyle())
                } else if let image = image(at: photoIndex) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                } else {
                    ContentUnavailableView(
                        "照片正在同步",
                        systemImage: "icloud.and.arrow.down",
                        description: Text("請稍後再開啟這個商品。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 270)
                    .background(.background)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.quaternary, lineWidth: 1)
            }

            if !photos.isEmpty {
                HStack {
                    Button {
                        isGalleryPresented = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .accessibilityLabel("瀏覽全部商品照片")

                    Spacer()

                    if photos.count > 1 {
                        HStack(spacing: 20) {
                            Button("上一張", systemImage: "chevron.left") {
                                photoIndex = max(0, photoIndex - 1)
                            }
                            .disabled(photoIndex == 0)

                            Text("\(photoIndex + 1) / \(photos.count)")
                                .font(.caption.bold())

                            Button("下一張", systemImage: "chevron.right") {
                                photoIndex = min(photos.count - 1, photoIndex + 1)
                            }
                            .disabled(photoIndex >= photos.count - 1)
                        }
                        .labelStyle(.iconOnly)
                    }

                    Spacer()

                    if photos.count < AppLimits.maximumPhotos {
                        PhotoSourceMenu(
                            maximumSelectionCount: AppLimits.maximumPhotos - photos.count,
                            onCamera: { openCamera() },
                            onPhotoData: { data in
                                Task { await addPhoto(data, saveToLibrary: false) }
                            },
                            onError: { alertMessage = $0 }
                        ) {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                        .accessibilityLabel("拍照或從相簿加入商品照片")
                    } else {
                        Button {
                            alertMessage = "每項商品最多可紀錄 5 張照片。"
                        } label: {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("商品照片已達5張上限")
                    }
                }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 4)
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("歷次採買紀錄")
                    .font(.title3.bold())
                Spacer()
                Picker("排列", selection: $recordSort) {
                    ForEach(PurchaseRecordSort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if product.sortedRecords.isEmpty {
                ContentUnavailableView(
                    "尚無採買紀錄",
                    systemImage: "cart.badge.questionmark"
                )
                .frame(minHeight: 180)
            } else {
                ForEach(displayedRecords) { record in
                    PurchaseRecordCard(
                        record: record,
                        onEdit: { recordBeingEdited = record },
                        onDelete: { recordPendingDeletion = record }
                    )
                }
            }
        }
    }

    private var priceMemorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPriceMemoryExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("價格記憶助手", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isPriceMemoryExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPriceMemoryExpanded {
                PriceMemoryDetails(product: product)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var comparisonRecordsSection: some View {
        let records = product.comparisonRecords.sorted { $0.recordedAt > $1.recordedAt }
        return VStack(alignment: .leading, spacing: 12) {
            Text("歷次比較價格")
                .font(.title3.bold())
            if records.isEmpty {
                Text("尚無可比較價格")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.recordedAt.formatted(date: .numeric, time: .shortened))
                            Spacer()
                            Text(record.formattedPrice).bold()
                        }
                        HStack {
                            Text(record.storeDisplayName)
                            Spacer()
                            Text(statusText(record.recordStatus))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if record.quantityWasEntered {
                            Text("單價 \(record.formattedEffectiveUnitPrice)")
                                .font(.caption)
                        } else {
                            Text("數量未填；原始價格仍納入比價")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            if let reference = record.referenceUnitPrice {
                                Text("依標示容量換算 \(reference.label)：\(SupportedCurrency.format(reference.value, code: record.normalizedCurrencyCode))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if record.id != records.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func image(at index: Int) -> UIImage? {
        guard photos.indices.contains(index) else { return nil }
        return ProductPhotoStore.load(photo: photos[index])
    }

    private func statusText(_ status: PurchaseRecordStatus) -> String {
        switch status {
        case .complete:
            return "完整資料"
        case .wishlistQuote:
            return "待買比價"
        case .quickDraft:
            return "暫存"
        case .comparison:
            return "比價資料"
        }
    }

    private var isOverseasOnlyProduct: Bool {
        let purchaseRecords = (product.records ?? []).filter { $0.recordStatus == .complete }
        return purchaseRecords.contains { $0.isForeignCurrencyPurchase }
            && !purchaseRecords.contains { !$0.isForeignCurrencyPurchase }
    }

    private var taiwanPantryAction: some View {
        Button {
            addToTaiwanPantry()
        } label: {
            Label(
                product.currentPantryEntry == nil ? "加入台灣食材庫" : "已顯示於台灣食材庫",
                systemImage: product.currentPantryEntry == nil ? "cabinet.fill" : "checkmark.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(product.currentPantryEntry != nil)
        .accessibilityHint("只建立食材庫登記，不新增台幣採買紀錄")
    }

    private func addToTaiwanPantry() {
        guard product.currentPantryEntry == nil else { return }
        let purchasedAt = (product.records ?? [])
            .filter { $0.recordStatus == .complete && $0.isForeignCurrencyPurchase }
            .max { $0.recordedAt < $1.recordedAt }?
            .recordedAt ?? .now
        let entry = PantryEntry(
            purchasedAt: purchasedAt,
            expirationDate: .now,
            product: product
        )
        modelContext.insert(entry)
        product.pantryEntries = (product.pantryEntries ?? []) + [entry]
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "食材庫", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }

    private func deleteRecord(_ record: PurchaseRecord) {
        do {
            modelContext.delete(record)
            try modelContext.save()
            recordPendingDeletion = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料刪除", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addPhoto(_ sourceData: Data, saveToLibrary: Bool = true) async {
        guard photos.count < AppLimits.maximumPhotos else {
            alertMessage = "每項商品最多可紀錄 5 張照片。"
            return
        }
        do {
            let imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            let photo = ProductPhoto(
                fileName: "",
                imageData: imageData,
                product: product
            )
            modelContext.insert(photo)
            try modelContext.save()
            if saveToLibrary {
                ProductPhotoStore.saveToPhotoLibrary(sourceData) { result in
                    if case .failure(let error) = result {
                        alertMessage = error.localizedDescription
                    }
                }
            }
            photoIndex = 0
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片儲存", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        guard ProductPhotoStore.isCameraAvailable else {
            alertMessage = "這台裝置沒有可用的相機，請改用 iPhone 實機測試。"
            return
        }
        isCameraPresented = true
    }
}

private struct RelatedProductsSection: View {
    let product: Product
    let allProducts: [Product]

    private var relatedProducts: [Product] {
        ProductSimilarity.related(to: product, among: allProducts)
    }

    var body: some View {
        if !relatedProducts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("同名或類似商品")
                    .font(.headline)
                ForEach(relatedProducts) { related in
                    NavigationLink {
                        ProductDetailView(product: related)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(related.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let record = related.latestPriceObservation {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(record.formattedPrice)
                                    Text("單價 \(record.formattedEffectiveUnitPrice)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("尚無價格")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    if related.id != relatedProducts.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct ProductIdentityCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LeadingInfoRow("條碼", product.barcodeDisplayText)
            LeadingInfoRow("名稱", product.name.isEmpty ? "未命名商品" : product.name)
            if !product.brand.isEmpty {
                LeadingInfoRow("品牌", product.brand)
            }
            if !product.manufacturerName.isEmpty {
                LeadingInfoRow("廠商", product.manufacturerName)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private enum PurchaseRecordSort: String, CaseIterable, Identifiable {
    case timeNewest = "時間"
    case priceLowest = "價格"
    case store = "店家"

    var id: Self { self }
}

private struct PurchaseRecordCard: View {
    let record: PurchaseRecord
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if record.isDraft {
                Label("暫存資料", systemImage: "tray.and.arrow.down.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            LeadingInfoRow("紀錄時間", record.recordedAt.formatted(date: .numeric, time: .shortened))
            LeadingInfoRow("店家", storeText)
            LeadingInfoRow("價格", record.formattedPrice)

            HStack {
                Button("編輯", systemImage: "pencil") {
                    onEdit()
                }
                .font(.caption.bold())

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "收合其他資料" : "展開其他資料")
                        .font(.caption.bold())
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(AppTheme.accent)

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    if !regionText.isEmpty {
                        LeadingInfoRow("區域", regionText)
                    }
                    LeadingInfoRow("購買數量", record.quantityWasEntered ? "\(record.purchaseQuantity)" : "未填寫")
                    LeadingInfoRow("有效單價", record.formattedEffectiveUnitPrice)
                    if let reference = record.referenceUnitPrice {
                        LeadingInfoRow(
                            reference.label,
                            SupportedCurrency.format(reference.value, code: record.normalizedCurrencyCode)
                        )
                    }
                    LeadingInfoRow("容（重）量", amountText)
                    LeadingInfoRow("單位", record.unit.isEmpty ? "未填寫" : record.unit)
                    checkRow("特價", checked: record.isOnSale)
                    checkRow("買一送一", checked: record.isBuyOneGetOne)
                    if let latitude = record.latitude, let longitude = record.longitude {
                        LeadingInfoRow(
                            "GPS座標",
                            String(format: "%.6f, %.6f", latitude, longitude),
                            valueFont: .caption
                        )
                    }
                    Button("刪除這筆紀錄", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var amountText: String {
        record.amount > 0
            ? record.amount.formatted(.number.precision(.fractionLength(0...2)))
            : "未填寫"
    }

    private var storeText: String {
        guard !record.store.isEmpty else { return "未填寫" }
        return record.storeBranch.isEmpty ? record.store : "\(record.store) \(record.storeBranch)"
    }

    private var regionText: String {
        [record.city, record.district].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func checkRow(_ title: String, checked: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? AppTheme.accent : .secondary)
                .accessibilityLabel(checked ? "是" : "否")
            Spacer(minLength: 0)
        }
    }
}

private struct PhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var product: Product
    @State private var alertMessage = ""
    @State private var photoBeingCropped: ProductPhoto?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(product.sortedPhotos) { photo in
                        if let image = ProductPhotoStore.load(photo: photo) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 20))

                                Button(role: .destructive) {
                                    delete(photo)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 30))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .red)
                                }
                                .padding(10)
                                .accessibilityLabel("刪除照片")

                                Button("裁切", systemImage: "crop") {
                                    photoBeingCropped = photo
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("商品照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $photoBeingCropped) { photo in
            if let image = ProductPhotoStore.load(photo: photo) {
                PhotoCropEditor(image: image) { croppedImage in
                    Task { await saveCrop(croppedImage, to: photo) }
                }
            }
        }
        .alert("無法刪除照片", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func delete(_ photo: ProductPhoto) {
        let fileName = photo.fileName
        modelContext.delete(photo)
        do {
            try modelContext.save()
            ProductPhotoStore.delete(fileName: fileName)
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片刪除", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveCrop(_ image: UIImage, to photo: ProductPhoto) async {
        guard let sourceData = image.jpegData(compressionQuality: 0.92) else {
            alertMessage = "無法產生裁切後的照片。"
            return
        }
        do {
            photo.imageData = try await ProductPhotoStore.optimizedJPEG(from: sourceData)
            photo.fileName = ""
            try modelContext.save()
            photoBeingCropped = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "照片裁切", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }
}

private struct PhotoCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onSave: (UIImage) -> Void
    @State private var preset: CropPreset = .square

    private var preview: UIImage { image.centerCropped(to: preset.ratio) ?? image }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.92))

                Picker("裁切比例", selection: $preset) {
                    ForEach(CropPreset.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .navigationTitle("裁切照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(preview)
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum CropPreset: String, CaseIterable, Identifiable {
    case square
    case landscape
    case portrait

    var id: Self { self }
    var title: String {
        switch self {
        case .square: "正方形"
        case .landscape: "4:3"
        case .portrait: "3:4"
        }
    }
    var ratio: CGFloat {
        switch self {
        case .square: 1
        case .landscape: 4 / 3
        case .portrait: 3 / 4
        }
    }
}

private extension UIImage {
    func centerCropped(to targetRatio: CGFloat) -> UIImage? {
        guard let cgImage, size.width > 0, size.height > 0 else { return nil }
        let sourceRatio = size.width / size.height
        let cropSize: CGSize
        if sourceRatio > targetRatio {
            cropSize = CGSize(width: size.height * targetRatio, height: size.height)
        } else {
            cropSize = CGSize(width: size.width, height: size.width / targetRatio)
        }
        let scaleX = CGFloat(cgImage.width) / size.width
        let scaleY = CGFloat(cgImage.height) / size.height
        let rect = CGRect(
            x: (size.width - cropSize.width) / 2 * scaleX,
            y: (size.height - cropSize.height) / 2 * scaleY,
            width: cropSize.width * scaleX,
            height: cropSize.height * scaleY
        ).integral
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
