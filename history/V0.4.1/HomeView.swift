import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.addedAt, order: .reverse) private var shoppingListItems: [ShoppingListItem]
    @Query private var products: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @State private var isScannerPresented = false
    @State private var scannedBarcode = ""
    @State private var scannerMessage = ""
    @State private var scanDestination: ScanDestination?
    @State private var pendingBarcode = ""
    @State private var isManualProductPending = false
    @State private var pendingScanIntent: ScanIntent = .purchase
    @State private var scannedProduct: Product?
    @State private var databaseError = ""
    @State private var shoppingItemPendingDeletion: ShoppingListItem?
    @State private var isForeignNameLookupPresented = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = HomeLayoutMetrics(width: geometry.size.width)

                VStack(spacing: 0) {
                    VStack(spacing: metrics.sectionSpacing) {
                        HStack(spacing: metrics.tileSpacing) {
                            HomeSquare(
                                title: "掃描條碼",
                                subtitle: "",
                                symbol: "camera.viewfinder",
                                color: .black,
                                fillColor: AppTheme.lightBlue,
                                iconSize: metrics.iconSize,
                                minimumHeight: metrics.tileHeight
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
                                    color: .orange,
                                    fillColor: .clear,
                                    iconSize: metrics.iconSize,
                                    minimumHeight: metrics.tileHeight
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        shoppingListSection
                        barcodeResult
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.topPadding)

                    AppFooter()
                        .frame(maxWidth: metrics.contentMaxWidth)
                }
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("購物記本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("設定")
                }
            }
        }
        .fullScreenCover(isPresented: $isScannerPresented, onDismiss: finishScanning) {
            BarcodeScannerSheet(onCode: { code in
                scannedBarcode = code
                scannerMessage = "條碼讀取完成"
                pendingBarcode = code
                isScannerPresented = false
            }, onNoBarcode: {
                scannedBarcode = ""
                pendingBarcode = ""
                isManualProductPending = true
                isScannerPresented = false
            })
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
            case .manualProduct(let identifier, let intent):
                NewProductView(
                    barcode: identifier,
                    isManualProduct: true,
                    onUseExisting: { product in
                        scannedProduct = product
                        scannedBarcode = product.barcode
                        if intent == .shoppingList {
                            addToShoppingList(product)
                        } else {
                            scannerMessage = "已選擇既有商品「\(product.name)」"
                        }
                    },
                    onSaved: { product in
                        scannedProduct = product
                        scannedBarcode = product.barcode
                        if intent == .shoppingList {
                            addToShoppingList(product)
                        } else {
                            scannerMessage = "已建立無條碼商品「\(product.name)」"
                        }
                    }
                )
            case .existingProduct(let product):
                ScannedProductView(product: product) {
                    scannerMessage = "已新增「\(product.name)」採買紀錄"
                }
            }
        }
        .sheet(isPresented: $isForeignNameLookupPresented) {
            ForeignNameLookupSheet(
                barcode: scannedBarcode,
                currentName: scannedProduct?.name ?? ""
            )
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
            Button(action: openLookupDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(scannerMessage, systemImage: scannedProduct == nil ? "questionmark.circle" : "tag.fill")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.up.circle.fill")
                            .foregroundStyle(.secondary)
                    }

                    if let product = scannedProduct {
                        Text(product.name.isEmpty ? "未命名商品" : product.name)
                            .font(.title3.bold())
                            .lineLimit(1)

                        if let latest = product.sortedRecords.first {
                            HStack(alignment: .firstTextBaseline) {
                                Text(latest.formattedEffectiveUnitPrice)
                                    .font(.title2.bold())
                                priceChangeLabel(for: product)
                                Spacer(minLength: 0)
                            }

                            Text("\(latest.storeDisplayName)・\(latest.recordedAt.formatted(date: .numeric, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("尚無價格紀錄")
                                .foregroundStyle(.secondary)
                        }

                        let related = ProductSimilarity.related(to: product, among: products, limit: 2)
                        if !related.isEmpty {
                            Divider()
                            Text("同名或類似商品")
                                .font(.caption.bold())
                            ForEach(related) { relatedProduct in
                                HStack {
                                    Text(relatedProduct.name)
                                        .lineLimit(1)
                                    Spacer()
                                    if let record = relatedProduct.latestRecord {
                                        Text("\(record.formattedPrice)・單價 \(record.formattedEffectiveUnitPrice)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    } else {
                        Text("條碼 \(scannedBarcode)")
                            .font(.subheadline.monospaced())
                            .lineLimit(1)
                        Text("尚無歷史價格，點擊建立商品資料")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("點擊查看照片、歷史價格與新增資料")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(resultTint), in: .rect(cornerRadius: 20))
            .accessibilityHint("開啟完整商品資料")

            if overseasModeEnabled {
                Button("查詢正確外文名稱", systemImage: "globe") {
                    isForeignNameLookupPresented = true
                }
                .font(.subheadline.bold())
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func priceChangeLabel(for product: Product) -> some View {
        let records = comparableRecords(for: product)
        if records.count >= 2 {
            let difference = records[0].effectiveUnitPrice - records[1].effectiveUnitPrice
            if abs(difference) < 0.005 {
                Text("與上次相同")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    SupportedCurrency.format(abs(difference), code: records[0].normalizedCurrencyCode),
                    systemImage: difference > 0 ? "arrow.up" : "arrow.down"
                )
                .foregroundStyle(difference > 0 ? .orange : AppTheme.accent)
            }
        } else {
            Text("目前僅一筆")
                .foregroundStyle(.secondary)
        }
    }

    private var resultTint: Color {
        guard let product = scannedProduct else {
            return .yellow.opacity(0.13)
        }
        let records = comparableRecords(for: product)
        guard records.count >= 2 else {
            return scannedProduct == nil ? .yellow.opacity(0.13) : AppTheme.lightBlue.opacity(0.16)
        }
        let difference = records[0].effectiveUnitPrice - records[1].effectiveUnitPrice
        if abs(difference) < 0.005 { return AppTheme.lightBlue.opacity(0.16) }
        return difference > 0 ? .orange.opacity(0.14) : AppTheme.accent.opacity(0.14)
    }

    private func comparableRecords(for product: Product) -> [PurchaseRecord] {
        guard let latest = product.sortedRecords.first else { return [] }
        return product.sortedRecords.filter {
            $0.normalizedCurrencyCode == latest.normalizedCurrencyCode
        }
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
                scannerMessage = "商品價格查詢完成"
            }
        } else {
            scannedProduct = nil
            if intent == .shoppingList {
                scanDestination = .newProduct(barcode, intent)
            } else {
                scannerMessage = "尚未建立商品資料"
            }
        }
    }

    private func finishScanning() {
        if isManualProductPending {
            isManualProductPending = false
            scanDestination = .manualProduct(ProductIdentifier.makeManual(), pendingScanIntent)
        } else {
            openScannedProduct()
        }
    }

    private func openLookupDetails() {
        guard !scannedBarcode.isEmpty else { return }
        if let scannedProduct {
            scanDestination = .existingProduct(scannedProduct)
        } else if databaseError.isEmpty {
            scanDestination = .newProduct(scannedBarcode, .purchase)
        } else {
            pendingBarcode = scannedBarcode
            pendingScanIntent = .purchase
            openScannedProduct()
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
        ViewThatFits(in: .horizontal) {
            fullRow
            compactRow
        }
    }

    private var fullRow: some View {
        HStack(spacing: 8) {
            Text(item.productName.isEmpty ? "未命名商品" : item.productName)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            barcodeAccessory(compact: false)

            Spacer(minLength: 0)

            deleteButton
        }
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            Text(item.productName.isEmpty ? "未命名商品" : item.productName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 0)

            barcodeAccessory(compact: true)
            deleteButton
        }
    }

    @ViewBuilder
    private func barcodeAccessory(compact: Bool) -> some View {
        if ProductIdentifier.isManual(item.barcode) {
            Text("無條碼")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        } else {
            Button {
                isBarcodePresented = true
            } label: {
                Text(compact ? "..." : item.barcode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("商品條碼 \(item.barcode)")
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
        }
    }

    private var deleteButton: some View {
        Button("刪除", systemImage: "trash", role: .destructive) {
            onDelete()
        }
        .labelStyle(.iconOnly)
    }
}

private enum ScanDestination: Identifiable {
    case newProduct(String, ScanIntent)
    case manualProduct(String, ScanIntent)
    case existingProduct(Product)

    var id: String {
        switch self {
        case .newProduct(let barcode, let intent):
            "new-\(intent)-\(barcode)"
        case .manualProduct(let identifier, let intent):
            "manual-\(intent)-\(identifier)"
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
    let fillColor: Color
    let iconSize: CGFloat
    let minimumHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeSquareLabel(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                color: color,
                fillColor: fillColor,
                iconSize: iconSize,
                minimumHeight: minimumHeight
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
    let fillColor: Color
    var iconSize: CGFloat = 42
    var minimumHeight: CGFloat = 108

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
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
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .background(fillColor, in: RoundedRectangle(cornerRadius: 24))
        .glassEffect(.regular.tint(color.opacity(0.10)).interactive(), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

private struct HomeLayoutMetrics {
    let horizontalPadding: CGFloat
    let sectionSpacing: CGFloat
    let tileSpacing: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let topPadding: CGFloat
    let contentMaxWidth: CGFloat

    init(width: CGFloat) {
        let isWidePhone = width >= 400
        horizontalPadding = isWidePhone ? 18 : 16
        sectionSpacing = isWidePhone ? 14 : 12
        tileSpacing = isWidePhone ? 14 : 12
        tileHeight = isWidePhone ? 116 : 108
        iconSize = isWidePhone ? 46 : 42
        topPadding = isWidePhone ? 8 : 4
        contentMaxWidth = 520
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
