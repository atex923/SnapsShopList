import SwiftData
import SwiftUI

struct ProductHistoryView: View {
    @Query private var products: [Product]

    private var sortedProducts: [Product] {
        products.sorted {
            ($0.latestRecord?.recordedAt ?? $0.createdAt) >
            ($1.latestRecord?.recordedAt ?? $1.createdAt)
        }
    }

    var body: some View {
        Group {
            if sortedProducts.isEmpty {
                ContentUnavailableView(
                    "尚無商品紀錄",
                    systemImage: "book.closed",
                    description: Text("請回首頁掃描條碼並建立第一筆商品資料。")
                )
            } else {
                List(sortedProducts) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        ProductSummaryRow(product: product)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("歷次商品紀錄")
        .navigationBarTitleDisplayMode(.inline)
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
                LabeledContent("店家", value: record.store.isEmpty ? "未填寫" : record.store)
                LabeledContent("價格", value: record.price.formatted(.currency(code: "TWD")))

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
