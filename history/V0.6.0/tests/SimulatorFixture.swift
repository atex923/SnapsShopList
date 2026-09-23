import Foundation
import SwiftData

@main
@MainActor
enum SimulatorFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: SimulatorFixture <seed|clear> <store-path>")
        }

        let action = CommandLine.arguments[1]
        let storeURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let schema = Schema([
            Product.self,
            PurchaseRecord.self,
            ProductPhoto.self,
            StorePreset.self,
            ShoppingListItem.self,
            PantryEntry.self
        ])
        let configuration = ModelConfiguration(
            "SnapshotBuyCheckLocal",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        try clear(context)
        if action == "seed" {
            try seed(context)
        } else if action != "clear" {
            fatalError("Unknown action: \(action)")
        }
        print("Simulator fixture \(action) passed")
    }

    private static func clear(_ context: ModelContext) throws {
        try context.fetch(FetchDescriptor<ShoppingListItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StorePreset>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<PantryEntry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<PurchaseRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ProductPhoto>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Product>()).forEach(context.delete)
        try context.save()
    }

    private static func seed(_ context: ModelContext) throws {
        let milk = Product(barcode: "4710123456789", name: "鮮乳家庭號測試商品")
        context.insert(milk)
        context.insert(PurchaseRecord(
            recordedAt: Date(timeIntervalSince1970: 1_750_000_000),
            store: "安心超市",
            storeBranch: "信義分店",
            city: "臺北市",
            district: "信義區",
            price: 105,
            amount: 1_850,
            unit: "ml",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: milk
        ))
        context.insert(PurchaseRecord(
            recordedAt: Date(timeIntervalSince1970: 1_760_000_000),
            store: "安心超市",
            storeBranch: "松山分店",
            city: "臺北市",
            district: "松山區",
            price: 99,
            amount: 1_850,
            unit: "ml",
            isOnSale: true,
            isBuyOneGetOne: false,
            product: milk
        ))

        let cereal = Product(barcode: "4710987654321", name: "超長名稱早餐穀物測試商品用來確認省略顯示")
        context.insert(cereal)
        context.insert(PurchaseRecord(
            store: "測試量販店",
            price: 159,
            amount: 500,
            unit: "g",
            isOnSale: true,
            isBuyOneGetOne: true,
            purchaseQuantity: 2,
            product: cereal
        ))

        context.insert(ShoppingListItem(productID: milk.id, barcode: milk.barcode, productName: milk.name))
        context.insert(ShoppingListItem(productID: cereal.id, barcode: cereal.barcode, productName: cereal.name))
        context.insert(PantryEntry(
            purchasedAt: Date(timeIntervalSince1970: 1_760_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_760_604_800),
            product: milk
        ))
        context.insert(PantryEntry(
            purchasedAt: Date(timeIntervalSince1970: 1_740_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_740_604_800),
            usedUpAt: Date(timeIntervalSince1970: 1_740_432_000),
            product: milk
        ))
        try context.save()
    }
}
