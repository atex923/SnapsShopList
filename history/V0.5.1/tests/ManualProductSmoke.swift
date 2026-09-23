import Foundation
import SwiftData

enum AppTheme {
    static let version = "V0.5.1-test"
}

@main
@MainActor
enum ManualProductSmoke {
    static func main() throws {
        let schema = Schema([
            Product.self,
            PurchaseRecord.self,
            ProductPhoto.self,
            StorePreset.self,
            ShoppingListItem.self,
            PantryEntry.self
        ])
        let configuration = ModelConfiguration(
            "SnapsShopListManualProductSmoke",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let identifier = ProductIdentifier.makeManual()
        precondition(ProductIdentifier.isManual(identifier))

        let product = Product(
            barcode: identifier,
            name: "市場蘋果",
            brand: "果園品牌",
            manufacturerName: "山田農園"
        )
        let record = PurchaseRecord(
            store: "傳統市場",
            price: 150,
            currencyCode: "TWD",
            amount: 750,
            unit: "g",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: product
        )
        context.insert(product)
        context.insert(record)
        context.insert(PurchaseRecord(
            recordedAt: record.recordedAt.addingTimeInterval(-60),
            store: "海外市場",
            price: 1,
            currencyCode: "JPY",
            amount: 750,
            unit: "g",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: product
        ))
        try context.save()

        precondition(product.isManualProduct)
        precondition(product.barcodeDisplayText == "無條碼")
        precondition(abs((record.pricePerHundred ?? 0) - 20) < 0.001)
        precondition(product.priceStatistics(currencyCode: "TWD")?.lowestRecord.id == record.id)
        precondition(product.priceStatistics(currencyCode: "JPY")?.lowestRecord.price == 1)

        let similar = Product(barcode: "4710000000001", name: "市場紅蘋果")
        precondition(ProductSimilarity.related(to: product, among: [product, similar]).first?.id == similar.id)

        let archive = try BackupManager.makeArchive(in: context)
        try BackupManager.validate(archive)
        precondition(archive.products.first?.barcode == identifier)

        try BackupManager.deleteAll(in: context)
        _ = try BackupManager.importArchive(archive, mode: .replace, in: context)

        let restored = try context.fetch(FetchDescriptor<Product>()).first
        precondition(restored?.isManualProduct == true)
        precondition(restored?.barcodeDisplayText == "無條碼")
        precondition(restored?.name == "市場蘋果")
        precondition(restored?.brand == "果園品牌")
        precondition(restored?.manufacturerName == "山田農園")
        precondition(restored?.records?.count == 2)

        print("Manual product smoke tests passed")
    }
}
