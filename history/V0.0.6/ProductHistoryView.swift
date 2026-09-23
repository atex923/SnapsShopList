import SwiftData
import SwiftUI

struct ProductHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var productPendingDeletion: Product?
    @State private var deletionError = ""

    private var sortedProducts: [Product] {
        let filtered = searchText.isEmpty ? products : products.filter { product in
            product.name.localizedStandardContains(searchText) ||
            product.barcode.localizedStandardContains(searchText) ||
            (product.latestRecord?.store.localizedStandardContains(searchText) ?? false) ||
            (product.latestRecord?.storeBranch.localizedStandardContains(searchText) ?? false) ||
            (product.latestRecord?.city.localizedStandardContains(searchText) ?? false) ||
            (product.latestRecord?.district.localizedStandardContains(searchText) ?? false)
        }

        return filtered.sorted {
            ($0.latestRecord?.recordedAt ?? $0.createdAt) >
            ($1.latestRecord?.recordedAt ?? $1.createdAt)
        }
    }

    var body: some View {
        Group {
            if products.isEmpty {
                ContentUnavailableView(
                    "尚無商品紀錄",
                    systemImage: "book.closed",
                    description: Text("請回首頁掃描條碼並建立第一筆商品資料。")
                )
            } else if sortedProducts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(sortedProducts) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        ProductSummaryRow(product: product)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            productPendingDeletion = product
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("歷次商品紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜尋商品、條碼或店家")
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
        let photoFileNames = product.sortedPhotos.map(\.fileName)
        let productID = product.id
        do {
            let listItems = try modelContext.fetch(FetchDescriptor<ShoppingListItem>())
                .filter { $0.productID == productID }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.name.isEmpty ? "未命名商品" : product.name)
                    .font(.headline)
                Spacer()
                Text(product.barcode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let record = product.latestRecord {
                LabeledContent("紀錄時間", value: record.recordedAt.formatted(date: .numeric, time: .shortened))
                LabeledContent("店家", value: storeText(record))
                let region = [record.city, record.district].filter { !$0.isEmpty }.joined(separator: " ")
                if !region.isEmpty {
                    LabeledContent("縣市區域", value: region)
                }
                LabeledContent("價格", value: record.price.formatted(.currency(code: "TWD")))
                LabeledContent("購買數量", value: "\(record.purchaseQuantity)")

                HStack(spacing: 8) {
                    if record.isOnSale {
                        StatusTag(text: "特價", color: .orange)
                    }
                    if record.isBuyOneGetOne {
                        StatusTag(text: "買一送一", color: AppTheme.accent)
                    }
                }
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
