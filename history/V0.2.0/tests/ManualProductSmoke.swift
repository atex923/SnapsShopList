import Foundation
import SwiftData

enum AppTheme {
    static let version = "V0.2.0-test"
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
            ShoppingListItem.self
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

        let product = Product(barcode: identifier, name: "市場蘋果")
        let record = PurchaseRecord(
            store: "傳統市場",
            price: 150,
            amount: 750,
            unit: "g",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: product
        )
        context.insert(product)
        context.insert(record)
        try context.save()

        precondition(product.isManualProduct)
        precondition(product.barcodeDisplayText == "無條碼")
        precondition(abs((record.pricePerHundred ?? 0) - 20) < 0.001)

        let archive = try BackupManager.makeArchive(in: context)
        try BackupManager.validate(archive)
        precondition(archive.products.first?.barcode == identifier)

        try BackupManager.deleteAll(in: context)
        _ = try BackupManager.importArchive(archive, mode: .replace, in: context)

        let restored = try context.fetch(FetchDescriptor<Product>()).first
        precondition(restored?.isManualProduct == true)
        precondition(restored?.barcodeDisplayText == "無條碼")
        precondition(restored?.name == "市場蘋果")

        print("Manual product smoke tests passed")
    }
}
