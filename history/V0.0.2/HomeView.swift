import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isScannerPresented = false
    @State private var scannedBarcode = ""
    @State private var scannerMessage = ""
    @State private var scanDestination: ScanDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 26) {
                        Text("食品採買與價格紀錄")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        GeometryReader { proxy in
                            let spacing: CGFloat = 18
                            let side = min((proxy.size.width - spacing) / 2, 168)

                            HStack(spacing: spacing) {
                                HomeSquare(
                                    title: "掃描條碼",
                                    subtitle: "啟動相機",
                                    symbol: "camera.viewfinder",
                                    color: AppTheme.accent,
                                    side: side
                                ) {
                                    isScannerPresented = true
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
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 168)

                        barcodeResult
                    }
                    .padding(.horizontal, 20)
                }

                AppFooter()
            }
            .background(AppTheme.background)
            .navigationTitle("採買記事工")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $isScannerPresented) {
            BarcodeScannerSheet { code in
                scannedBarcode = code
                scannerMessage = "條碼讀取完成"
                isScannerPresented = false
                findProduct(for: code)
            }
        }
        .sheet(item: $scanDestination) { destination in
            switch destination {
            case .newProduct(let barcode):
                NewProductView(barcode: barcode) { productName in
                    scannerMessage = "已建立「\(productName)」"
                }
            case .existingProduct(let product):
                NewPurchaseView(product: product) {
                    scannerMessage = "已新增「\(product.name)」採買紀錄"
                }
            }
        }
    }

    @ViewBuilder
    private var barcodeResult: some View {
        if scannedBarcode.isEmpty {
            ContentUnavailableView(
                "尚未掃描條碼",
                systemImage: "barcode.viewfinder",
                description: Text("點擊左上方相機圖案開始讀取食品條碼。")
            )
            .frame(minHeight: 220)
        } else {
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
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        }
    }

    private func findProduct(for barcode: String) {
        var descriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { product in
                product.barcode == barcode
            }
        )
        descriptor.fetchLimit = 1
        let product = (try? modelContext.fetch(descriptor))?.first

        // 等掃描相機的 sheet 完成關閉後再呈現資料表單。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let product {
                scanDestination = .existingProduct(product)
            } else {
                scanDestination = .newProduct(barcode)
            }
        }
    }
}

private enum ScanDestination: Identifiable {
    case newProduct(String)
    case existingProduct(Product)

    var id: String {
        switch self {
        case .newProduct(let barcode):
            "new-\(barcode)"
        case .existingProduct(let product):
            "existing-\(product.id.uuidString)"
        }
    }
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
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(color)
        .frame(width: side, height: side)
        .background(.background, in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: color.opacity(0.12), radius: 14, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 26))
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
