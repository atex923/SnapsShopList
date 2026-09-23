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
                committedSearchText.isEmpty
                    || $0.name.localizedStandardContains(committedSearchText)
                    || $0.barcode.localizedStandardContains(committedSearchText)
            }
            .sorted {
                let left = $0.latestRecord?.recordedAt ?? $0.createdAt
                let right = $1.latestRecord?.recordedAt ?? $1.createdAt
                if left != right { return left > right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if products.isEmpty {
                ContentUnavailableView(
                    "尚無商品資料",
                    systemImage: "cabinet.fill",
                    description: Text("先掃描條碼或建立無條碼商品，再加入食材庫。")
                )
            } else if visibleProducts.isEmpty {
                ContentUnavailableView.search(text: committedSearchText)
            } else {
                List(visibleProducts) { product in
                    PantryProductRow(product: product)
                }
                .listStyle(.plain)
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
            .frame(minHeight: 50)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(AppTheme.background)
    }
}

struct OverseasPurchaseLibraryView: View {
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var committedSearchText = ""

    private var visibleProducts: [Product] {
        products
            .filter { product in
                guard !product.sortedRecords.isEmpty else { return false }
                return committedSearchText.isEmpty
                    || product.name.localizedStandardContains(committedSearchText)
                    || product.barcode.localizedStandardContains(committedSearchText)
                    || product.sortedRecords.contains {
                        $0.storeDisplayName.localizedStandardContains(committedSearchText)
                    }
            }
            .sorted {
                let left = $0.latestRecord?.recordedAt ?? $0.createdAt
                let right = $1.latestRecord?.recordedAt ?? $1.createdAt
                if left != right { return left > right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if products.allSatisfy({ $0.sortedRecords.isEmpty }) {
                ContentUnavailableView(
                    "尚無購物紀錄",
                    systemImage: "globe",
                    description: Text("新增採買資料後，會依商品整理不同時間的數量、價格與店家。")
                )
            } else if visibleProducts.isEmpty {
                ContentUnavailableView.search(text: committedSearchText)
            } else {
                List(visibleProducts) { product in
                    OverseasPurchaseProductRow(product: product)
                }
                .listStyle(.plain)
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
            .frame(minHeight: 50)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(AppTheme.background)
    }
}

private struct OverseasPurchaseProductRow: View {
    let product: Product
    @State private var isExpanded = false

    private var records: [PurchaseRecord] { product.sortedRecords }
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
                    DatePicker("購入時間", selection: $purchasedAt, displayedComponents: [.date])
                        .disabled(!isEditing)
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Text("保存期限")
                        DatePicker(
                            "保存期限日期",
                            selection: $expirationDate,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .tint(.red)
                        .foregroundStyle(.red)
                        .colorMultiply(.red)
                        .disabled(!isEditing)
                        Spacer(minLength: 0)
                    }

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
            purchasedAt = product.latestRecord?.recordedAt ?? .now
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
                LabeledContent("最新購入時間", value: latest.purchasedAt.formatted(date: .numeric, time: .omitted))
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
                        LabeledContent("購入時間", value: entry.purchasedAt.formatted(date: .numeric, time: .omitted))
                        LabeledContent("保存期限", value: entry.expirationDate.formatted(date: .numeric, time: .omitted))
                        if let usedUpAt = entry.usedUpAt {
                            LabeledContent("已用畢", value: usedUpAt.formatted(date: .numeric, time: .shortened))
                        } else {
                            Text("目前在庫")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .font(.subheadline)
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
