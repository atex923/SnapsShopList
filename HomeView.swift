import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var quickModeSession: QuickModeSession
    @Query(sort: \ShoppingListItem.addedAt, order: .reverse) private var shoppingListItems: [ShoppingListItem]
    @Query private var products: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage(QuickModeSettings.showToggleKey) private var showQuickModeToggle = false
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
    @State private var quickEntryRequest: QuickEntryRequest?
    @State private var quickFullEntryRequest: QuickFullEntryRequest?
    @State private var latestQuickDraft: QuickDraft?

    private var activeCurrencyCode: String {
        PurchaseCurrencyPolicy.activeCode(
            overseasModeEnabled: overseasModeEnabled,
            preferredCode: UserDefaults.standard.string(forKey: "SnapsShopList.defaultCurrencyCode") ?? SupportedCurrency.TWD.rawValue
        )
    }

    private var visibleShoppingListItems: [ShoppingListItem] {
        shoppingListItems.filter { item in
            overseasModeEnabled
                ? item.currencyCode != SupportedCurrency.TWD.rawValue
                : item.currencyCode == SupportedCurrency.TWD.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = HomeLayoutMetrics(width: geometry.size.width)

                VStack(spacing: 0) {
                    VStack(spacing: metrics.sectionSpacing) {
                        if quickModeSession.isEnabled {
                            Spacer(minLength: metrics.sectionSpacing)
                            quickModeMascot(metrics: metrics)
                            Spacer(minLength: metrics.sectionSpacing * 1.5)
                            quickCaptureSection
                            Spacer(minLength: max(42, metrics.sectionSpacing * 3))
                        } else {
                            HStack(spacing: metrics.tileSpacing) {
                                HomeSquare(
                                    title: "掃描條碼",
                                    subtitle: "",
                                    symbol: "camera.viewfinder",
                                    color: .black,
                                    fillColor: overseasModeEnabled ? AppTheme.overseasCamera : AppTheme.lightBlue,
                                    iconSize: metrics.iconSize * 1.3,
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
                            inventorySection
                            ZStack(alignment: .bottom) {
                                homeMascot(metrics: metrics)
                                    .padding(.top, scannedBarcode.isEmpty ? 0 : 34)
                                barcodeResult
                                    .padding(.bottom, scannedBarcode.isEmpty ? 0 : 42)
                            }
                            if let latestQuickDraft {
                                quickDraftCard(latestQuickDraft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.topPadding)

                    AppFooter()
                        .frame(maxWidth: metrics.contentMaxWidth)
                }
                .frame(maxWidth: .infinity)
            }
            .appModeBackground()
            .navigationTitle("購物記本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("設定")
                }
                if showQuickModeToggle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle("快速模式", isOn: $quickModeSession.isEnabled)
                            .labelsHidden()
                            .accessibilityLabel("快速模式")
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SNAPS_DEBUG_QUICK_MODE"] == "1" {
                showQuickModeToggle = true
                quickModeSession.isEnabled = true
            }
            #endif
            QuickDraftStore.cleanupExpiredDrafts()
            latestQuickDraft = QuickDraftStore.latestDraft()
        }
        .onChange(of: showQuickModeToggle) { _, isVisible in
            if !isVisible { quickModeSession.isEnabled = false }
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
                if intent == .shoppingList {
                    WishlistProductView(barcode: barcode) { product in
                        scannedProduct = product
                        addToShoppingList(product)
                    }
                } else {
                    NewProductView(barcode: barcode) { product in
                        scannedProduct = product
                        scannerMessage = "已建立「\(product.name)」"
                    }
                }
            case .manualProduct(let identifier, let intent):
                if intent == .shoppingList {
                    WishlistProductView(barcode: identifier, isManualProduct: true) { product in
                        scannedProduct = product
                        scannedBarcode = product.barcode
                        addToShoppingList(product)
                    }
                } else {
                    NewProductView(
                        barcode: identifier,
                        isManualProduct: true,
                        onUseExisting: { product in
                            scannedProduct = product
                            scannedBarcode = product.barcode
                            scannerMessage = "已選擇既有商品「\(product.name)」"
                        },
                        onSaved: { product in
                            scannedProduct = product
                            scannedBarcode = product.barcode
                            scannerMessage = "已建立無條碼商品「\(product.name)」"
                        }
                    )
                }
            case .existingProduct(let product):
                ScannedProductView(product: product) {
                    scannerMessage = "已新增「\(product.name)」採買紀錄"
                }
            case .newPurchase(let product):
                NewPurchaseView(product: product) {
                    scannedProduct = product
                    scannedBarcode = product.barcode
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
        .sheet(item: $quickEntryRequest) { request in
            QuickEntryView(request: request) { result in
                latestQuickDraft = QuickDraftStore.latestDraft()
                if let product = result.product {
                    scannedProduct = product
                    scannedBarcode = product.barcode
                    scannerMessage = result.completed ? "快速紀錄已正式儲存" : "快速草稿已暫存"
                } else if let draft = result.draft {
                    scannedBarcode = draft.barcode
                    scannerMessage = "快速草稿已暫存"
                }
            }
        }
        .sheet(item: $quickFullEntryRequest) { request in
            if let product = request.product {
                NewPurchaseView(product: product, quickDraft: request.draft) {
                    latestQuickDraft = QuickDraftStore.latestDraft()
                    scannedProduct = product
                    scannedBarcode = product.barcode
                    scannerMessage = "已新增「\(product.name)」採買紀錄"
                }
            } else {
                NewProductView(
                    barcode: request.barcode,
                    isManualProduct: ProductIdentifier.isManual(request.barcode),
                    quickDraft: request.draft,
                    onSaved: { product in
                        latestQuickDraft = QuickDraftStore.latestDraft()
                        scannedProduct = product
                        scannedBarcode = product.barcode
                        scannerMessage = "已建立「\(product.name)」"
                    }
                )
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
            if let product = scannedProduct, !quickModeSession.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(scannerMessage, systemImage: "tag.fill")
                            .font(.headline)
                        Spacer()
                        Button {
                            scanDestination = .existingProduct(product)
                        } label: {
                            Image(systemName: "chevron.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看商品歷史價格")
                    }

                    Text(product.name.isEmpty ? "未命名商品" : product.name)
                        .font(.title3.bold())
                        .lineLimit(1)

                    if let latest = product.latestPriceObservation {
                        HStack(alignment: .firstTextBaseline) {
                            Text(latest.quantityWasEntered ? latest.formattedEffectiveUnitPrice : latest.formattedPrice)
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

                    Button {
                        scanDestination = .newPurchase(product)
                    } label: {
                        Text("新購買")
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.18), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.red.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(ImmediatePressStyle())
                    .accessibilityLabel("新購買")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(.regular.tint(resultTint), in: .rect(cornerRadius: 20))
            } else {
                Button(action: openLookupDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(scannerMessage, systemImage: "questionmark.circle")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.up.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        Text("條碼 \(scannedBarcode)")
                            .font(.subheadline.monospaced())
                            .lineLimit(1)
                        Text(quickModeSession.isEnabled ? "點擊快速紀錄" : "點擊建立資料")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(resultTint), in: .rect(cornerRadius: 20))
                .accessibilityHint("建立商品資料")
            }

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
        guard let latest = product.latestPriceObservation else { return [] }
        return product.comparisonRecords.filter {
            $0.normalizedCurrencyCode == latest.normalizedCurrencyCode && $0.quantityWasEntered
        }
        .sorted {
            $0.recordedAt > $1.recordedAt
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
        if quickModeSession.isEnabled {
            quickFullEntryRequest = QuickFullEntryRequest(
                barcode: scannedBarcode,
                product: scannedProduct,
                draft: nil
            )
            return
        }
        if let scannedProduct {
            scanDestination = .newPurchase(scannedProduct)
        } else if databaseError.isEmpty {
            scanDestination = .newProduct(scannedBarcode, .purchase)
        } else {
            pendingBarcode = scannedBarcode
            pendingScanIntent = .purchase
            openScannedProduct()
        }
    }

    private var quickCaptureSection: some View {
        Button {
            quickEntryRequest = QuickEntryRequest(
                barcode: ProductIdentifier.makeManual(),
                product: nil,
                draft: nil,
                opensCameraImmediately: true
            )
        } label: {
            HStack(spacing: 18) {
                Image(systemName: "camera.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .white)
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 68, height: 68)
                    .background(Color.blue, in: Circle())
                    .shadow(color: .blue.opacity(0.32), radius: 8, y: 5)

                Text("快速紀錄")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(ImmediatePressStyle())
        .glassEffect(.regular.tint(.blue.opacity(0.10)).interactive(), in: .rect(cornerRadius: 24))
        .accessibilityLabel("快速拍照紀錄")
    }

    private func quickDraftCard(_ draft: QuickDraft) -> some View {
        Button {
            let product = products.first { $0.id == draft.productID || $0.barcode == draft.barcode }
            quickFullEntryRequest = QuickFullEntryRequest(
                barcode: draft.barcode,
                product: product,
                draft: draft
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("待完成快速草稿", systemImage: "tray.and.arrow.down.fill")
                        .font(.headline)
                    Text(draft.name.trimmed.isEmpty ? draft.barcodeDisplayText : draft.name)
                        .lineLimit(1)
                    Text("\(draft.formattedPrice)・\(draft.updatedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(14)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 20))
    }

    private var shoppingListSection: some View {
        HStack(spacing: 12) {
            Button {
                pendingScanIntent = .shoppingList
                isManualProductPending = true
                finishScanning()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title2.bold())
                    Text("建立商品")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(ImmediatePressStyle())
            .glassEffect(.regular.tint(AppTheme.accent.opacity(0.10)).interactive(), in: .rect(cornerRadius: 20))
            .accessibilityHint("建立待買商品，可拍照掃描或從相簿讀取條碼")

            NavigationLink {
                ShoppingListView()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: visibleShoppingListItems.isEmpty ? "cart" : "cart.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 30)
                        .background(visibleShoppingListItems.isEmpty ? Color.white : Color.clear)
                    Text("待買清單")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(ImmediatePressStyle())
            .glassEffect(.regular.tint(.blue.opacity(0.10)).interactive(), in: .rect(cornerRadius: 20))
        }
    }

    private var pantrySection: some View {
        NavigationLink {
            PantryView()
        } label: {
            HStack(spacing: 12) {
                Label("食材庫", systemImage: "cabinet.fill")
                    .font(.title3.bold())
                Spacer()
                if !scannedBarcode.isEmpty,
                   let pantryStatus = PantryHomeStatus.status(for: scannedProduct) {
                    if pantryStatus == .usedUp {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("掃描商品已用畢")
                    } else {
                        Text("在庫")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                            .accessibilityLabel("掃描商品目前在庫")
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color(red: 0.88, green: 0.79, blue: 0.66), in: RoundedRectangle(cornerRadius: 20))
            .glassEffect(.regular.tint(.brown.opacity(0.10)).interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(ImmediatePressStyle())
    }

    @ViewBuilder
    private var inventorySection: some View {
        if overseasModeEnabled {
            overseasPurchaseLibrarySection
        } else {
            pantrySection
        }
    }

    private var overseasPurchaseLibrarySection: some View {
        NavigationLink {
            OverseasPurchaseLibraryView()
        } label: {
            HStack(spacing: 12) {
                Label("海外購物數量庫", systemImage: "globe")
                    .font(.title3.bold())
                Spacer()
                if let product = scannedProduct {
                    let count = product.sortedRecords.filter { $0.recordStatus == .complete && $0.isForeignCurrencyPurchase && $0.quantityWasEntered }.count
                    if count > 0 {
                        Text("\(count) 筆")
                            .font(.caption.bold())
                            .foregroundStyle(.indigo)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color(red: 0.84, green: 0.86, blue: 0.97), in: RoundedRectangle(cornerRadius: 20))
            .glassEffect(.regular.tint(.indigo.opacity(0.10)).interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(ImmediatePressStyle())
    }

    private func startScanning(for intent: ScanIntent) {
        pendingScanIntent = intent
        isScannerPresented = true
    }

    private func addToShoppingList(_ product: Product) {
        do {
            let currencyCode = activeCurrencyCode
            if let existing = shoppingListItems.first(where: { $0.productID == product.id && $0.currencyCode == currencyCode }) {
                existing.desiredQuantity += 1
                existing.addedAt = .now
            } else {
                modelContext.insert(ShoppingListItem(
                    productID: product.id,
                    barcode: product.barcode,
                    productName: product.name,
                    currencyCode: currencyCode
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

    @ViewBuilder
    private func homeMascot(metrics: HomeLayoutMetrics) -> some View {
        let isShowingResult = !scannedBarcode.isEmpty
        Image(isShowingResult ? "MascotProne" : "MascotStanding")
            .resizable()
            .scaledToFit()
            .frame(
                maxWidth: metrics.contentMaxWidth * (isShowingResult ? 0.70 : 0.38),
                maxHeight: isShowingResult ? 132 : 150
            )
            .opacity(0.96)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isShowingResult)
    }

    private func quickModeMascot(metrics: HomeLayoutMetrics) -> some View {
        Image("MascotRunning")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: metrics.contentMaxWidth * 0.78, maxHeight: 260)
            .opacity(0.96)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.addedAt, order: .reverse) private var items: [ShoppingListItem]
    @Query private var products: [Product]
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @State private var quickEntryRequest: QuickEntryRequest?
    @State private var itemPendingDeletion: ShoppingListItem?
    @State private var errorMessage = ""

    private var visibleItems: [ShoppingListItem] {
        items.filter {
            overseasModeEnabled
                ? $0.currencyCode != SupportedCurrency.TWD.rawValue
                : $0.currencyCode == SupportedCurrency.TWD.rawValue
        }
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                ContentUnavailableView(
                    "待買清單尚無資料",
                    systemImage: "cart",
                    description: Text("回首頁使用左側的建立商品按鈕加入待買資料。")
                )
            } else {
                List(visibleItems) { item in
                    HStack(spacing: 10) {
                        if let product = product(for: item) {
                            NavigationLink {
                                ProductDetailView(product: product)
                            } label: {
                                shoppingItemLabel(item)
                            }
                        } else {
                            shoppingItemLabel(item)
                        }

                        Button {
                            guard let product = product(for: item) else {
                                errorMessage = "找不到這項待買商品的資料，請重新建立。"
                                return
                            }
                            quickEntryRequest = QuickEntryRequest(
                                barcode: product.barcode,
                                product: product,
                                draft: nil,
                                opensCameraImmediately: true
                            )
                        } label: {
                            Image(systemName: "camera.fill")
                        }
                        .buttonStyle(RaisedGlassIconButtonStyle())
                        .accessibilityLabel("快速記錄 \(item.productName)")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            itemPendingDeletion = item
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appModeBackground()
        .navigationTitle("待買清單")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $quickEntryRequest) { request in
            QuickEntryView(request: request) { _ in }
        }
        .confirmationDialog(
            "從待買清單刪除商品？",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let item = itemPendingDeletion { delete(item) }
            }
            Button("取消", role: .cancel) { itemPendingDeletion = nil }
        } message: {
            Text("只會從待買清單移除，不會刪除商品或採買紀錄。")
        }
        .alert("待買清單", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func product(for item: ShoppingListItem) -> Product? {
        products.first { $0.id == item.productID }
            ?? products.first { !ProductIdentifier.isManual(item.barcode) && $0.barcode == item.barcode }
    }

    private func shoppingItemLabel(_ item: ShoppingListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.productName.isEmpty ? "未命名商品" : item.productName)
                .font(.headline)
                .lineLimit(1)
            Text(ProductIdentifier.isManual(item.barcode) ? "無條碼商品" : item.barcode)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func delete(_ item: ShoppingListItem) {
        modelContext.delete(item)
        do {
            try modelContext.save()
            itemPendingDeletion = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "待買清單", context: item.barcode)
            errorMessage = error.localizedDescription
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
    case newPurchase(Product)

    var id: String {
        switch self {
        case .newProduct(let barcode, let intent):
            "new-\(intent)-\(barcode)"
        case .manualProduct(let identifier, let intent):
            "manual-\(intent)-\(identifier)"
        case .existingProduct(let product):
            "existing-\(product.id.uuidString)"
        case .newPurchase(let product):
            "purchase-\(product.id.uuidString)"
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
                .frame(height: 64)
            Text(title)
                .font(.headline)
                .frame(height: 24)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 18)
        }
        .offset(y: 6)
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
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : 0.18),
                radius: configuration.isPressed ? 2 : 7,
                y: configuration.isPressed ? 1 : 5
            )
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}
