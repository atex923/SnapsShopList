import SwiftData
import SwiftUI

struct ProductHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var productPendingDeletion: Product?
    @State private var deletionError = ""

    private var rows: [ProductHistoryRow] {
        products.compactMap { product in
            let row = ProductHistoryRow(
                product: product,
                latestRecord: product.latestRecord,
                lowestRecord: product.priceStatistics?.lowestRecord
            )
            guard searchText.isEmpty || row.matches(searchText) else { return nil }
            return row
        }
        .sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        Group {
            if products.isEmpty {
                ContentUnavailableView(
                    "尚無商品紀錄",
                    systemImage: "book.closed",
                    description: Text("請回首頁掃描條碼，或建立第一筆無條碼商品。")
                )
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(rows) { row in
                    NavigationLink {
                        ProductDetailView(product: row.product)
                    } label: {
                        ProductSummaryRow(product: row.product, record: row.lowestRecord)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            productPendingDeletion = row.product
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("歷次商品紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜尋商品、品牌、廠商、條碼或店家")
        .confirmationDialog(
            "刪除商品及全部歷史紀錄？",
            isPresented: Binding(
                get: { productPendingDeletion != nil },
                set: { if !$0 { productPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除商品", role: .destructive) {
                if let product = productPendingDeletion { deleteProduct(product) }
            }
            Button("取消", role: .cancel) { productPendingDeletion = nil }
        } message: {
            Text("商品、採買紀錄及 App 內商品照片都會刪除，此動作無法復原。")
        }
        .alert("無法刪除", isPresented: Binding(
            get: { !deletionError.isEmpty },
            set: { if !$0 { deletionError = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deletionError)
        }
    }

    private func deleteProduct(_ product: Product) {
        let photoFileNames = product.sortedPhotos.map(\.fileName).filter { !$0.isEmpty }
        let productID = product.id
        do {
            let descriptor = FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate<ShoppingListItem> { $0.productID == productID }
            )
            let listItems = try modelContext.fetch(descriptor)
            listItems.forEach(modelContext.delete)
            modelContext.delete(product)
            try modelContext.save()
            photoFileNames.forEach(ProductPhotoStore.delete)
            productPendingDeletion = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料刪除", context: product.barcode)
            deletionError = error.localizedDescription
        }
    }
}

private struct ProductSummaryRow: View {
    let product: Product
    let record: PurchaseRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.name.isEmpty ? "未命名商品" : product.name)
                .font(.headline)

            if let record {
                if (product.records ?? []).contains(where: { $0.isDraft }) {
                    Label("暫存資料，可點入編輯", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                LabeledContent("最低價格", value: record.formattedEffectiveUnitPrice)
                LabeledContent("店家", value: storeText(record))
                LabeledContent("紀錄時間", value: record.recordedAt.formatted(date: .numeric, time: .shortened))
            } else {
                Text("尚無採買資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 4)
    }

    private func storeText(_ record: PurchaseRecord) -> String {
        guard !record.store.isEmpty else { return "未填寫" }
        return record.storeBranch.isEmpty ? record.store : "\(record.store) \(record.storeBranch)"
    }
}

private struct ProductHistoryRow: Identifiable {
    let product: Product
    let latestRecord: PurchaseRecord?
    let lowestRecord: PurchaseRecord?
    var id: UUID { product.id }
    var sortDate: Date { latestRecord?.recordedAt ?? product.createdAt }

    func matches(_ text: String) -> Bool {
        product.name.localizedStandardContains(text) ||
        product.brand.localizedStandardContains(text) ||
        product.manufacturerName.localizedStandardContains(text) ||
        product.barcode.localizedStandardContains(text) ||
        (latestRecord?.store.localizedStandardContains(text) ?? false) ||
        (latestRecord?.storeBranch.localizedStandardContains(text) ?? false) ||
        (latestRecord?.city.localizedStandardContains(text) ?? false) ||
        (latestRecord?.district.localizedStandardContains(text) ?? false)
    }
}

struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
