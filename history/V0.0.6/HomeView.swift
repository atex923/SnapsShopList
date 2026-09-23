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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    GeometryReader { proxy in
                        let spacing: CGFloat = 12
                        let side = (proxy.size.width - spacing) / 2

                        HStack(spacing: spacing) {
                            HomeSquare(
                                title: "掃描條碼",
                                subtitle: "啟動相機",
                                symbol: "camera.viewfinder",
                                color: AppTheme.accent,
                                side: side
                            ) {
                                startScanning(for: .purchase)
                            }

                            NavigationLink {
                                ProductHistoryView()
                            } label: {
                                HomeSquareLabel(
                                    title: "採買記事",
                                    subtitle: "歷次紀錄",
                                    symbol: "book.pages",
                                    color: .orange,
                                    side: side
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 148)

                    shoppingListSection
                    barcodeResult
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                AppFooter()
            }
            .background(AppTheme.background)
            .navigationTitle("快拍購物帳本")
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
                NewPurchaseView(product: product) {
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
                        priceSummary("平均", statistics.averageEffectivePrice)
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
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.productName.isEmpty ? "未命名商品" : item.productName)
                                .font(.headline)
                            Text(item.barcode)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("減少", systemImage: "minus.circle") {
                            changeShoppingQuantity(item, by: -1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(item.desiredQuantity <= 1)
                        Text("\(item.desiredQuantity)")
                            .monospacedDigit()
                            .frame(minWidth: 24)
                        Button("增加", systemImage: "plus.circle") {
                            changeShoppingQuantity(item, by: 1)
                        }
                        .labelStyle(.iconOnly)
                        Button("移除", systemImage: "trash", role: .destructive) {
                            deleteShoppingItem(item)
                        }
                        .labelStyle(.iconOnly)
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

    private func changeShoppingQuantity(_ item: ShoppingListItem, by change: Int) {
        item.desiredQuantity = max(1, item.desiredQuantity + change)
        saveShoppingList(context: item.barcode)
    }

    private func deleteShoppingItem(_ item: ShoppingListItem) {
        modelContext.delete(item)
        saveShoppingList(context: item.barcode)
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
    let side: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeSquareLabel(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                color: color,
                side: side
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
    let side: CGFloat

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
        .frame(width: side, height: side)
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
