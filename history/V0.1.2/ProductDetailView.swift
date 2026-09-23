import SwiftData
import SwiftUI

struct ScannedProductView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                    priceTable

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
            .background(AppTheme.background)
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
            CameraPhotoPicker(onPhotoData: { data in
                isCameraPresented = false
                let replacedPhoto = photoBeingReplaced
                photoBeingReplaced = nil
                Task { await savePhoto(data, replacing: replacedPhoto) }
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
                    Button {
                        photoBeingReplaced = nil
                        openCamera()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 58))
                            Text("拍攝商品照片")
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

                    Button {
                        photoBeingReplaced = photos[photoIndex]
                        openCamera()
                    } label: {
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

                ForEach(product.sortedRecords) { record in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(record.recordedAt.formatted(date: .numeric, time: .shortened))
                        Text(record.storeDisplayName)
                            .lineLimit(2)
                        Text(record.price.formatted(.currency(code: "TWD")))
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
    private func savePhoto(_ sourceData: Data, replacing photo: ProductPhoto?) async {
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
            ProductPhotoStore.saveToPhotoLibrary(sourceData) { result in
                if case .failure(let error) = result { alertMessage = error.localizedDescription }
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
            product.sortedRecords
        case .priceLowest:
            (product.records ?? []).sorted {
                if $0.price == $1.price { return $0.recordedAt > $1.recordedAt }
                return $0.price < $1.price
            }
        case .store:
            (product.records ?? []).sorted {
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
                recordsSection
                priceMemorySection
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(product.name.isEmpty ? "商品資料" : product.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoPicker(onPhotoData: { data in
                isCameraPresented = false
                Task { await addPhoto(data) }
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
                    Button {
                        openCamera()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 58))
                            Text("拍攝商品照片")
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

                    Button {
                        if photos.count < 3 {
                            openCamera()
                        } else {
                            alertMessage = "每項商品最多可紀錄 3 張照片。"
                        }
                    } label: {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityLabel("更新商品照片")
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
                    .padding(.leading, 18)
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
    private func addPhoto(_ sourceData: Data) async {
        guard photos.count < 3 else {
            alertMessage = "每項商品最多可紀錄 3 張照片。"
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
            ProductPhotoStore.saveToPhotoLibrary(sourceData) { result in
                if case .failure(let error) = result {
                    alertMessage = error.localizedDescription
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

private enum PurchaseRecordSort: String, CaseIterable, Identifiable {
    case timeNewest = "時間（最新）"
    case priceLowest = "價格（最低）"
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
            LabeledContent("紀錄時間", value: record.recordedAt.formatted(date: .numeric, time: .shortened))
            LabeledContent("店家", value: storeText)
            LabeledContent("價格", value: record.price.formatted(.currency(code: "TWD")))

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
                VStack(spacing: 9) {
                    if !regionText.isEmpty {
                        LabeledContent("縣市區域", value: regionText)
                    }
                    LabeledContent("購買數量", value: "\(record.purchaseQuantity)")
                    LabeledContent("有效單價", value: record.effectiveUnitPrice.formatted(.currency(code: "TWD")))
                    if let pricePerHundred = record.pricePerHundred, let unit = record.normalizedUnitLabel {
                        LabeledContent("每 100 \(unit)", value: pricePerHundred.formatted(.currency(code: "TWD")))
                    }
                    LabeledContent("容（重）量", value: amountText)
                    LabeledContent("單位", value: record.unit.isEmpty ? "未填寫" : record.unit)
                    checkRow("特價", checked: record.isOnSale)
                    checkRow("買一送一", checked: record.isBuyOneGetOne)
                    if let latitude = record.latitude, let longitude = record.longitude {
                        LabeledContent(
                            "GPS",
                            value: String(format: "%.6f, %.6f", latitude, longitude)
                        )
                        if let accuracy = record.locationAccuracy {
                            LabeledContent("定位誤差", value: String(format: "約 %.0f 公尺", accuracy))
                        }
                    }
                    Button("刪除這筆紀錄", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.leading, 18)
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
        HStack {
            Text(title)
            Spacer()
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? AppTheme.accent : .secondary)
                .accessibilityLabel(checked ? "是" : "否")
        }
    }
}

private struct PhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var product: Product
    @State private var alertMessage = ""

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
}
