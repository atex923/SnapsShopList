import SwiftData
import SwiftUI

struct ProductDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var product: Product
    @State private var photoIndex = 0
    @State private var isCameraPresented = false
    @State private var isGalleryPresented = false
    @State private var alertMessage = ""

    private var photos: [ProductPhoto] { product.sortedPhotos }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                photoSection
                recordsSection
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(product.name.isEmpty ? "商品資料" : product.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCameraPresented) {
            CameraPhotoPicker { image in
                addPhoto(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isGalleryPresented) {
            PhotoGalleryView(product: product)
        }
        .onChange(of: photos.count) { _, newCount in
            photoIndex = min(photoIndex, max(0, newCount - 1))
        }
        .alert("照片處理失敗", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var photoSection: some View {
        ZStack(alignment: .bottom) {
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
                    }
                    .accessibilityLabel("更新商品照片")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(14)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("歷次採買紀錄")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if product.sortedRecords.isEmpty {
                ContentUnavailableView(
                    "尚無採買紀錄",
                    systemImage: "cart.badge.questionmark"
                )
                .frame(minHeight: 180)
            } else {
                ForEach(product.sortedRecords) { record in
                    PurchaseRecordCard(record: record)
                }
            }
        }
    }

    private func image(at index: Int) -> UIImage? {
        guard photos.indices.contains(index) else { return nil }
        return ProductPhotoStore.load(photo: photos[index])
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < 3 else {
            alertMessage = "每項商品最多可紀錄 3 張照片。"
            return
        }
        var savedFileName: String?
        do {
            let imageData = try ProductPhotoStore.jpegData(for: image)
            let fileName = try ProductPhotoStore.save(imageData)
            savedFileName = fileName
            let photo = ProductPhoto(
                fileName: fileName,
                imageData: imageData,
                product: product
            )
            modelContext.insert(photo)
            try modelContext.save()
            ProductPhotoStore.saveToPhotoLibrary(image)
            photoIndex = 0
        } catch {
            modelContext.rollback()
            if let savedFileName {
                ProductPhotoStore.delete(fileName: savedFileName)
            }
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

private struct PurchaseRecordCard: View {
    let record: PurchaseRecord

    var body: some View {
        VStack(spacing: 9) {
            LabeledContent("紀錄時間", value: record.recordedAt.formatted(date: .numeric, time: .shortened))
            LabeledContent("店家", value: storeText)
            if !regionText.isEmpty {
                LabeledContent("縣市區域", value: regionText)
            }
            LabeledContent("價格", value: record.price.formatted(.currency(code: "TWD")))
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
        }
        .font(.subheadline)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var amountText: String {
        record.amount.formatted(.number.precision(.fractionLength(0...2)))
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
