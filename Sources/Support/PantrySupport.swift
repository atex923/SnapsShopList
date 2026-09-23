import SwiftData
import SwiftUI
import UIKit

struct PantryView: View {
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var committedSearchText = ""

    private var visibleProducts: [Product] {
        products
            .filter {
                let isTaiwanPantryProduct = ($0.records ?? []).contains {
                    $0.normalizedCurrencyCode == SupportedCurrency.TWD.rawValue
                } || !($0.pantryEntries ?? []).isEmpty
                let matchesSearch = committedSearchText.isEmpty
                    || $0.name.localizedStandardContains(committedSearchText)
                    || $0.barcode.localizedStandardContains(committedSearchText)
                return isTaiwanPantryProduct && matchesSearch
            }
            .sorted(by: PantryProductOrdering.precedes)
    }

    private var hasTaiwanPantryProducts: Bool {
        products.contains {
            ($0.records ?? []).contains { $0.normalizedCurrencyCode == SupportedCurrency.TWD.rawValue }
                || !($0.pantryEntries ?? []).isEmpty
        }
    }

    var body: some View {
        Group {
            if !hasTaiwanPantryProducts {
                ContentUnavailableView(
                    "尚無商品資料",
                    systemImage: "cabinet.fill",
                    description: Text("台幣商品會顯示在這裡；海外商品可從商品資料加入台灣食材庫。")
                )
            } else if visibleProducts.isEmpty {
                ContentUnavailableView.search(text: committedSearchText)
            } else {
                List(visibleProducts) { product in
                    PantryProductRow(product: product)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("食材庫")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                ComposingAwareSearchField(
                    text: $searchText,
                    committedText: $committedSearchText,
                    placeholder: "搜尋商品"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .layoutPriority(1)
                if !searchText.isEmpty {
                    Button("清除", systemImage: "xmark.circle.fill") {
                        searchText = ""
                        committedSearchText = ""
                    }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .appModeBackground()
    }
}

struct OverseasPurchaseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var committedSearchText = ""
    @State private var recordBeingEdited: PurchaseRecord?
    @State private var recordPendingDeletion: PurchaseRecord?
    @State private var isClearAllConfirmationPresented = false
    @State private var alertMessage = ""
    @State private var pickerMode: OverseasProductPickerMode?
    @State private var selectedProduct: Product?
    @State private var isManualProductPresented = false

    private var foreignRecords: [PurchaseRecord] {
        products.flatMap { foreignRecords(for: $0) }
    }

    private var visibleProducts: [Product] {
        products
            .filter { product in
                let records = foreignRecords(for: product)
                guard !records.isEmpty else { return false }
                return committedSearchText.isEmpty
                    || product.name.localizedStandardContains(committedSearchText)
                    || product.barcode.localizedStandardContains(committedSearchText)
                    || records.contains {
                        $0.storeDisplayName.localizedStandardContains(committedSearchText)
                    }
            }
            .sorted {
                let left = foreignRecords(for: $0).first?.recordedAt ?? $0.createdAt
                let right = foreignRecords(for: $1).first?.recordedAt ?? $1.createdAt
                if left != right { return left > right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if foreignRecords.isEmpty {
                ContentUnavailableView(
                    "尚無海外購物紀錄",
                    systemImage: "globe",
                    description: Text("非台幣採買資料會依商品整理不同時間的數量、價格與店家。")
                )
            } else if visibleProducts.isEmpty {
                ContentUnavailableView.search(text: committedSearchText)
            } else {
                List(visibleProducts) { product in
                    OverseasPurchaseProductRow(
                        product: product,
                        records: foreignRecords(for: product),
                        onEdit: { recordBeingEdited = $0 },
                        onDelete: { recordPendingDeletion = $0 }
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("海外購物數量庫")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                ComposingAwareSearchField(
                    text: $searchText,
                    committedText: $committedSearchText,
                    placeholder: "搜尋商品或店家"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .layoutPriority(1)
                if !searchText.isEmpty {
                    Button("清除", systemImage: "xmark.circle.fill") {
                        searchText = ""
                        committedSearchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .appModeBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("從海外庫勾選", systemImage: "checklist") {
                        pickerMode = .overseasLibrary
                    }
                    Button("從資料庫勾選", systemImage: "externaldrive") {
                        pickerMode = .allProducts
                    }
                    Button("建立資料庫（無條碼後補）", systemImage: "tag.slash") {
                        isManualProductPresented = true
                    }
                } label: {
                    Label("加入海外採買", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除全部", systemImage: "trash", role: .destructive) {
                    isClearAllConfirmationPresented = true
                }
                .disabled(foreignRecords.isEmpty)
            }
        }
        .sheet(item: $recordBeingEdited) { record in
            EditPurchaseView(record: record)
        }
        .sheet(item: $pickerMode) { mode in
            OverseasProductPicker(
                mode: mode,
                products: products,
                onSelect: { product in
                    pickerMode = nil
                    DispatchQueue.main.async { selectedProduct = product }
                }
            )
        }
        .sheet(item: $selectedProduct) { product in
            NewPurchaseView(product: product) { selectedProduct = nil }
        }
        .sheet(isPresented: $isManualProductPresented) {
            NewProductView(
                barcode: ProductIdentifier.makeManual(),
                isManualProduct: true,
                onSaved: { _ in isManualProductPresented = false }
            )
        }
        .confirmationDialog(
            "刪除這筆海外購物紀錄？",
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
        } message: {
            Text("只會刪除這筆非台幣採買資料，商品、照片與台幣紀錄會保留。")
        }
        .confirmationDialog(
            "清除全部海外購物紀錄？",
            isPresented: $isClearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("全部清除", role: .destructive) { clearAllForeignRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("會刪除所有非台幣採買紀錄，供下次海外購物重新記錄；商品、照片、食材庫與台幣紀錄不受影響。")
        }
        .alert("海外購物庫操作失敗", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func foreignRecords(for product: Product) -> [PurchaseRecord] {
        product.sortedRecords.filter { $0.recordStatus == .complete && $0.isForeignCurrencyPurchase && $0.quantityWasEntered }
    }

    private func deleteRecord(_ record: PurchaseRecord) {
        do {
            modelContext.delete(record)
            try modelContext.save()
            recordPendingDeletion = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "海外購物紀錄刪除", context: record.product?.barcode ?? "")
            alertMessage = error.localizedDescription
        }
    }

    private func clearAllForeignRecords() {
        do {
            for record in foreignRecords {
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "海外購物紀錄清除")
            alertMessage = error.localizedDescription
        }
    }
}

private enum OverseasProductPickerMode: String, Identifiable {
    case overseasLibrary
    case allProducts

    var id: String { rawValue }
    var title: String { self == .overseasLibrary ? "從海外庫勾選" : "從資料庫勾選" }
}

private struct OverseasProductPicker: View {
    @Environment(\.dismiss) private var dismiss
    let mode: OverseasProductPickerMode
    let products: [Product]
    let onSelect: (Product) -> Void
    @State private var searchText = ""

    private var visibleProducts: [Product] {
        products
            .filter { product in
                let isEligible = mode == .allProducts
                    || product.sortedRecords.contains { $0.recordStatus == .complete && $0.isForeignCurrencyPurchase && $0.quantityWasEntered }
                let matches = searchText.isEmpty
                    || product.name.localizedStandardContains(searchText)
                    || product.barcode.localizedStandardContains(searchText)
                return isEligible && matches
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(visibleProducts) { product in
                Button {
                    onSelect(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.name.isEmpty ? "未命名商品" : product.name)
                                .foregroundStyle(.primary)
                            Text(product.barcodeDisplayText)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "square")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appModeBackground()
            .searchable(text: $searchText, prompt: "搜尋商品")
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .appModeBackground()
    }
}

private struct OverseasPurchaseProductRow: View {
    let product: Product
    let records: [PurchaseRecord]
    let onEdit: (PurchaseRecord) -> Void
    let onDelete: (PurchaseRecord) -> Void
    @State private var isExpanded = false

    private var totalQuantity: Int { records.reduce(0) { $0 + max(1, $1.purchaseQuantity) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name.isEmpty ? "未命名商品" : product.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("共 \(records.count) 筆・購買數量 \(totalQuantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.recordedAt.formatted(date: .numeric, time: .shortened))
                            Spacer()
                            Text(record.formattedPrice)
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Label(record.storeDisplayName, systemImage: "storefront")
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text("數量 \(max(1, record.purchaseQuantity))")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Button("編輯", systemImage: "pencil") { onEdit(record) }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("刪除", systemImage: "trash", role: .destructive) {
                                onDelete(record)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.subheadline)
                    .padding(.leading, 16)
                    if record.id != records.last?.id { Divider() }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PantryProductRow: View {
    @Environment(\.modelContext) private var modelContext
    let product: Product

    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var purchasedAt = Date.now
    @State private var expirationDate = Date.now
    @State private var alertMessage = ""
    @State private var isUsedUpConfirmationPresented = false

    private var currentEntry: PantryEntry? { product.currentPantryEntry }
    private var isShownAsInStock: Bool { currentEntry != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleSelection) {
                HStack(spacing: 12) {
                    Text(product.name.isEmpty ? "未命名商品" : product.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: isShownAsInStock ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isShownAsInStock ? AppTheme.accent : .secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(currentEntry == nil ? "將商品加入食材庫" : "展開食材庫資料")

            if isExpanded {
                Divider()
                VStack(spacing: 12) {
                    PantryDateRow(title: "購入時間", selection: $purchasedAt, isEditing: isEditing)
                    PantryDateRow(title: "保存期限", selection: $expirationDate, isEditing: isEditing, dateColor: .red)

                    HStack {
                        if currentEntry != nil, isEditing {
                            Button("已用畢", role: .destructive) {
                                isUsedUpConfirmationPresented = true
                            }
                        }
                        Spacer()
                        if currentEntry != nil, !isEditing {
                            Button("編輯", systemImage: "pencil") { isEditing = true }
                        }
                        if isEditing {
                            Button("取消") { cancelEditing() }
                                .buttonStyle(.bordered)
                            Button("確定", systemImage: "checkmark") { save() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
        .onAppear { loadCurrentValues() }
        .alert("食材庫無法儲存", isPresented: Binding(
            get: { !alertMessage.isEmpty },
            set: { if !$0 { alertMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "確認標記為已用畢？",
            isPresented: $isUsedUpConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("標記為已用畢", role: .destructive) { markUsedUp() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這會結束目前的在庫狀態，但仍會保留食材庫歷史。")
        }
    }

    private func toggleSelection() {
        if currentEntry == nil {
            purchasedAt = product.latestPurchaseRecord?.recordedAt ?? .now
            expirationDate = .now
            isEditing = true
            isExpanded = true
        } else {
            loadCurrentValues()
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    private func loadCurrentValues() {
        guard let entry = currentEntry else { return }
        purchasedAt = entry.purchasedAt
        expirationDate = entry.expirationDate
        isEditing = false
    }

    private func cancelEditing() {
        if currentEntry != nil {
            loadCurrentValues()
        } else {
            purchasedAt = .now
            expirationDate = .now
            isEditing = false
            isExpanded = false
        }
    }

    private func save() {
        do {
            if let entry = currentEntry {
                entry.purchasedAt = purchasedAt
                entry.expirationDate = expirationDate
            } else {
                let newEntry = PantryEntry(
                    purchasedAt: purchasedAt,
                    expirationDate: expirationDate,
                    product: product
                )
                modelContext.insert(newEntry)
                if !(product.pantryEntries ?? []).contains(where: { $0.id == newEntry.id }) {
                    product.pantryEntries = (product.pantryEntries ?? []) + [newEntry]
                }
            }
            try modelContext.save()
            isEditing = false
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "食材庫", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }

    private func markUsedUp() {
        guard let entry = currentEntry else { return }
        do {
            entry.usedUpAt = .now
            try modelContext.save()
            isExpanded = false
            isEditing = false
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "食材庫", context: product.barcode)
            alertMessage = error.localizedDescription
        }
    }
}

private struct ComposingAwareSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var committedText: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .search
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if text.isEmpty, !(textField.text ?? "").isEmpty {
            textField.unmarkText()
            textField.text = ""
            return
        }
        guard textField.markedTextRange == nil, textField.text != text else { return }
        textField.text = text
    }

    final class Coordinator: NSObject {
        var parent: ComposingAwareSearchField

        init(parent: ComposingAwareSearchField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            let value = textField.text ?? ""
            parent.text = value
            guard textField.markedTextRange == nil else { return }
            parent.committedText = value
        }
    }
}

struct PantryHistorySection: View {
    let product: Product
    @State private var isExpanded = false

    private var entries: [PantryEntry] { product.sortedPantryEntries }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !entries.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("食材庫", systemImage: "cabinet.fill")
                        .font(.title3.bold())
                    Spacer()
                    if !entries.isEmpty {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let latest = entries.first {
                LabeledContent("購入時間", value: PantryDateFormatter.string(from: latest.purchasedAt))
                    .font(.caption)
                if product.currentPantryEntry != nil {
                    Label("目前在庫", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                        .font(.subheadline.bold())
                }
            } else {
                Text("尚未登記食材庫")
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Divider()
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent("購入時間", value: PantryDateFormatter.string(from: entry.purchasedAt))
                            .font(.caption)
                        HStack {
                            Text("保存期限")
                            Spacer()
                            Text(PantryDateFormatter.string(from: entry.expirationDate))
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                        if let usedUpAt = entry.usedUpAt {
                            LabeledContent("已用畢", value: usedUpAt.formatted(date: .numeric, time: .shortened))
                        } else {
                            Text("目前在庫")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.leading, 16)
                    if entry.id != entries.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

enum PantryDateFormatter {
    private static let gregorianFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        let rocYear = Calendar(identifier: .republicOfChina).component(.year, from: date)
        return "\(gregorianFormatter.string(from: date))(\(rocYear))"
    }
}

private struct PantryDateRow: View {
    let title: String
    @Binding var selection: Date
    let isEditing: Bool
    var dateColor: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 82, alignment: .leading)
            Spacer(minLength: 0)
            PantryInlineDatePicker(selection: $selection, isEditing: isEditing, dateColor: dateColor)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

private struct PantryInlineDatePicker: View {
    @Binding var selection: Date
    let isEditing: Bool
    var dateColor: Color = .primary

    var body: some View {
        if isEditing {
            ZStack {
                Text(PantryDateFormatter.string(from: selection))
                    .foregroundStyle(dateColor)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(dateColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                DatePicker(
                    "日期",
                    selection: $selection,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .opacity(0.015)
            }
            .accessibilityElement(children: .contain)
        } else {
            Text(PantryDateFormatter.string(from: selection))
                .foregroundStyle(dateColor)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
