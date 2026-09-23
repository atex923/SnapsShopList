import SwiftData
import SwiftUI

struct ProductHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @State private var searchText = ""
    @State private var productPendingDeletion: Product?
    @State private var deletionError = ""
    @State private var quickFullEntryRequest: QuickFullEntryRequest?
    @State private var draftRefreshToken = UUID()

    private var rows: [ProductHistoryRow] {
        products.compactMap { product in
            let purchaseRecords = product.sortedRecords.filter { record in
                return overseasModeEnabled
                    ? record.normalizedCurrencyCode != SupportedCurrency.TWD.rawValue
                    : record.normalizedCurrencyCode == SupportedCurrency.TWD.rawValue
            }
            guard let latestRecord = purchaseRecords.first else { return nil }
            let row = ProductHistoryRow(
                product: product,
                latestRecord: latestRecord,
                lowestRecord: product.priceStatistics(currencyCode: latestRecord.normalizedCurrencyCode)?.lowestRecord
            )
            guard searchText.isEmpty || row.matches(searchText) else { return nil }
            return row
        }
        .sorted { $0.sortDate > $1.sortDate }
    }

    private var quickDrafts: [QuickDraft] {
        _ = draftRefreshToken
        return QuickDraftStore.allDrafts()
            .filter { draft in
                let matchesMode = overseasModeEnabled
                    ? draft.currencyCode != SupportedCurrency.TWD.rawValue
                    : draft.currencyCode == SupportedCurrency.TWD.rawValue
                guard matchesMode else { return false }
                guard !searchText.isEmpty else { return true }
                return draft.name.localizedStandardContains(searchText) ||
                    draft.barcode.localizedStandardContains(searchText) ||
                    draft.store.localizedStandardContains(searchText) ||
                    draft.city.localizedStandardContains(searchText) ||
                    draft.district.localizedStandardContains(searchText)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var hasVisibleItems: Bool { !rows.isEmpty || !quickDrafts.isEmpty }

    var body: some View {
        Group {
            if !hasVisibleItems && searchText.isEmpty {
                ContentUnavailableView(
                    "尚無商品紀錄",
                    systemImage: "book.closed",
                    description: Text("請回首頁掃描條碼，或建立第一筆無條碼商品。")
                )
            } else if !hasVisibleItems {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    if !quickDrafts.isEmpty {
                        Section("快速暫存") {
                            ForEach(quickDrafts) { draft in
                                Button {
                                    openQuickDraft(draft)
                                } label: {
                                    QuickDraftSummaryRow(draft: draft)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    if !rows.isEmpty {
                        Section("採買商品") {
                            ForEach(rows) { row in
                                NavigationLink {
                                    ProductDetailView(product: row.product)
                                } label: {
                                    ProductSummaryRow(
                                        product: row.product,
                                        latestRecord: row.latestRecord,
                                        lowestRecord: row.lowestRecord
                                    )
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("刪除", systemImage: "trash", role: .destructive) {
                                        productPendingDeletion = row.product
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appModeBackground()
        .navigationTitle("歷次商品紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜尋商品、品牌、廠商、條碼或店家")
        .onAppear { draftRefreshToken = UUID() }
        .sheet(item: $quickFullEntryRequest) { request in
            if let product = request.product {
                NewPurchaseView(product: product, quickDraft: request.draft) {
                    draftRefreshToken = UUID()
                }
            } else {
                NewProductView(
                    barcode: request.barcode,
                    isManualProduct: ProductIdentifier.isManual(request.barcode),
                    quickDraft: request.draft,
                    onSaved: { _ in draftRefreshToken = UUID() }
                )
            }
        }
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

    private func openQuickDraft(_ draft: QuickDraft) {
        let matchingProduct = products.first { product in
            if let productID = draft.productID, product.id == productID { return true }
            return !ProductIdentifier.isManual(draft.barcode) && product.barcode == draft.barcode
        }
        quickFullEntryRequest = QuickFullEntryRequest(
            barcode: draft.barcode,
            product: matchingProduct,
            draft: draft
        )
    }
}

private struct QuickDraftSummaryRow: View {
    let draft: QuickDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.name.trimmed.isEmpty ? "未命名商品" : draft.name)
                .font(.headline)
            Label("暫存資料，可點入繼續編輯", systemImage: "tray.and.arrow.down.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            LabeledContent("條碼", value: draft.barcodeDisplayText)
            LabeledContent("價格", value: draft.formattedPrice)
            LabeledContent("店家", value: draft.store.trimmed.isEmpty ? "未填寫" : draft.store)
            LabeledContent("暫存時間", value: draft.updatedAt.formatted(date: .numeric, time: .shortened))
        }
        .font(.subheadline)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProductSummaryRow: View {
    let product: Product
    let latestRecord: PurchaseRecord?
    let lowestRecord: PurchaseRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.name.isEmpty ? "未命名商品" : product.name)
                .font(.headline)

            if let record = latestRecord {
                if (product.records ?? []).contains(where: { $0.isDraft }) {
                    Label("暫存資料，可點入編輯", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                LabeledContent("購買總價", value: record.formattedPrice)
                if let lowestRecord {
                    LabeledContent("單品最低", value: lowestRecord.formattedEffectiveUnitPrice)
                }
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
