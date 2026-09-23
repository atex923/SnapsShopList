import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.addedAt, order: .reverse) private var shoppingListItems: [ShoppingListItem]
    @State private var isScannerPresented = false
    @State private var scannedBarcode = ""
    @State private var scannerMessage = ""
    @State private var scanDestination: ScanDestination?
    @State private var pendingBarcode = ""
    @State private var pendingScanIntent: ScanIntent = .purchase
    @State private var scannedProduct: Product?
    @State private var databaseError = ""
    @State private var shoppingItemPendingDeletion: ShoppingListItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                            HomeSquare(
                                title: "掃描條碼",
                                subtitle: "",
                                symbol: "camera.viewfinder",
                                color: AppTheme.mutedBlue
                            ) {
                                startScanning(for: .purchase)
                            }

                            NavigationLink {
                                ProductHistoryView()
                            } label: {
                                HomeSquareLabel(
                                    title: "採買記事",
                                    subtitle: "",
                                    symbol: "book.pages",
                                    color: .orange
                                )
                            }
                            .buttonStyle(.plain)
                    }

                    shoppingListSection
                    barcodeResult
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                AppFooter()
            }
            .background(AppTheme.background)
            .navigationTitle("購物記本")
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(isPresented: $isScannerPresented, onDismiss: openScannedProduct) {
            BarcodeScannerSheet { code in
                scannedBarcode = code
                scannerMessage = "條碼讀取完成"
                pendingBarcode = code
                isScannerPresented = false
            }
        }
        .sheet(item: $scanDestination) { destination in
            switch destination {
            case .newProduct(let barcode, let intent):
                NewProductView(barcode: barcode) { product in
                    scannedProduct = product
                    if intent == .shoppingList {
                        addToShoppingList(product)
                    } else {
                        scannerMessage = "已建立「\(product.name)」"
                    }
                }
            case .existingProduct(let product):
                ScannedProductView(product: product) {
                    scannerMessage = "已新增「\(product.name)」採買紀錄"
                }
            }
        }
        .alert("資料庫查詢失敗", isPresented: Binding(
            get: { !databaseError.isEmpty },
            set: { if !$0 { databaseError = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(databaseError)
        }
        .confirmationDialog(
            "從待買清單刪除商品？",
            isPresented: Binding(
                get: { shoppingItemPendingDeletion != nil },
                set: { if !$0 { shoppingItemPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let item = shoppingItemPendingDeletion { deleteShoppingItem(item) }
            }
            Button("取消", role: .cancel) { shoppingItemPendingDeletion = nil }
        } message: {
            Text("只會從待買清單移除，不會刪除商品的歷史資料。")
        }
    }

    @ViewBuilder
    private var barcodeResult: some View {
        if !scannedBarcode.isEmpty {
            VStack(spacing: 12) {
                Label(scannerMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.headline)

                Text(scannedBarcode)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)

                Text("掃描後會自動比對商品資料庫")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let statistics = scannedProduct?.priceStatistics {
                    Divider()
                    HStack {
                        priceSummary("最低", statistics.lowestRecord.effectiveUnitPrice)
                        Divider()
                        priceSummary("最高", statistics.highestRecord.effectiveUnitPrice)
                    }
                    .frame(height: 42)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .glassEffect(.regular.tint(.white.opacity(0.22)), in: .rect(cornerRadius: 20))
        }
    }

    private func priceSummary(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: "TWD")))
                .font(.caption.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func openScannedProduct() {
        guard !pendingBarcode.isEmpty else { return }
        let barcode = pendingBarcode
        let intent = pendingScanIntent
        pendingBarcode = ""

        var descriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { product in
                product.barcode == barcode
            }
        )
        descriptor.fetchLimit = 1
        let product: Product?
        do {
            product = try modelContext.fetch(descriptor).first
        } catch {
            scannerMessage = "條碼已讀取，但無法查詢資料庫"
            AppErrorLogger.record(error, category: "資料庫查詢", context: "條碼 \(barcode)")
            databaseError = error.localizedDescription
            return
        }

        if let product {
            scannedProduct = product
            if intent == .shoppingList {
                addToShoppingList(product)
            } else {
                scanDestination = .existingProduct(product)
            }
        } else {
            scannedProduct = nil
            scanDestination = .newProduct(barcode, intent)
        }
    }

    private var shoppingListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("待買清單", systemImage: "cart")
                    .font(.title3.bold())
                Spacer()
                Button("掃描加入", systemImage: "barcode.viewfinder") {
                    startScanning(for: .shoppingList)
                }
            }

            if shoppingListItems.isEmpty {
                Text("尚無待買商品，可掃描條碼從既有商品資料庫加入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(shoppingListItems.prefix(2))) { item in
                    ShoppingListCompactRow(item: item) {
                        shoppingItemPendingDeletion = item
                    }
                    .padding(.vertical, 5)
                    if item.id != shoppingListItems.last?.id { Divider() }
                }
                if shoppingListItems.count > 2 {
                    Text("另有 \(shoppingListItems.count - 2) 項，掃描或移除後會自動更新。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(.white.opacity(0.24)), in: .rect(cornerRadius: 20))
    }

    private func startScanning(for intent: ScanIntent) {
        pendingScanIntent = intent
        isScannerPresented = true
    }

    private func addToShoppingList(_ product: Product) {
        do {
            if let existing = shoppingListItems.first(where: { $0.productID == product.id }) {
                existing.desiredQuantity += 1
                existing.addedAt = .now
            } else {
                modelContext.insert(ShoppingListItem(
                    productID: product.id,
                    barcode: product.barcode,
                    productName: product.name
                ))
            }
            try modelContext.save()
            scannerMessage = "已將「\(product.name)」加入待買清單"
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "待買清單", context: product.barcode)
            databaseError = error.localizedDescription
        }
    }

    private func deleteShoppingItem(_ item: ShoppingListItem) {
        modelContext.delete(item)
        saveShoppingList(context: item.barcode)
        shoppingItemPendingDeletion = nil
    }

    private func saveShoppingList(context: String) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "待買清單", context: context)
            databaseError = error.localizedDescription
        }
    }
}

private struct ShoppingListCompactRow: View {
    let item: ShoppingListItem
    let onDelete: () -> Void
    @State private var isBarcodePresented = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.productName.isEmpty ? "未命名商品" : item.productName)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)

            Button {
                isBarcodePresented = true
            } label: {
                Text(item.barcode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 112)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isBarcodePresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("商品條碼")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.barcode)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }

            Spacer(minLength: 0)

            Button("刪除", systemImage: "trash", role: .destructive) {
                onDelete()
            }
            .labelStyle(.iconOnly)
        }
    }
}

private enum ScanDestination: Identifiable {
    case newProduct(String, ScanIntent)
    case existingProduct(Product)

    var id: String {
        switch self {
        case .newProduct(let barcode, let intent):
            "new-\(intent)-\(barcode)"
        case .existingProduct(let product):
            "existing-\(product.id.uuidString)"
        }
    }
}

private enum ScanIntent: String {
    case purchase
    case shoppingList
}

private struct HomeSquare: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeSquareLabel(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                color: color
            )
        }
        .buttonStyle(ImmediatePressStyle())
    }
}

struct HomeSquareLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 52)
            Text(title)
                .font(.headline)
                .frame(height: 24)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 18)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .glassEffect(.regular.tint(color.opacity(0.10)).interactive(), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

struct ImmediatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}
