import Foundation
import SwiftData

enum AppTheme {
    static let version = "V0.11.2-test"
}

@main
@MainActor
enum BackupSupportSmoke {
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
            "SnapsShopListBackupSmoke",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let product = Product(
            barcode: "4710000000001",
            name: "測試牛奶",
            brand: "測試品牌",
            manufacturerName: "測試食品公司"
        )
        context.insert(product)

        let record = PurchaseRecord(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            store: "測試商店",
            storeBranch: "一號店",
            city: "臺北市",
            district: "信義區",
            price: 89,
            currencyCode: "USD",
            amount: 1_000,
            unit: "ml",
            isOnSale: true,
            isBuyOneGetOne: false,
            purchaseQuantity: 2,
            isGroupPackage: true,
            groupContentCount: 4,
            latitude: 25.033,
            longitude: 121.565,
            locationAccuracy: 8,
            product: product
        )
        context.insert(record)

        let previousRecord = PurchaseRecord(
            recordedAt: Date(timeIntervalSince1970: 1_600_000_000),
            store: "舊價格商店",
            price: 120,
            currencyCode: "USD",
            amount: 1_000,
            unit: "ml",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: product
        )
        context.insert(previousRecord)

        let photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        context.insert(ProductPhoto(fileName: "", imageData: photoData, product: product))
        context.insert(StorePreset(name: "測試商店", branch: "一號店", city: "臺北市", district: "信義區"))
        context.insert(ShoppingListItem(productID: product.id, barcode: product.barcode, productName: product.name))
        let pantryEntry = PantryEntry(
            purchasedAt: record.recordedAt,
            expirationDate: record.recordedAt.addingTimeInterval(86400 * 7),
            product: product
        )
        context.insert(pantryEntry)
        try context.save()

        let archive = try BackupManager.makeArchive(in: context)
        precondition(archive.schemaVersion == 5)
        precondition(archive.products.count == 1)
        precondition(archive.recordCount == 2)
        precondition(archive.photoCount == 1)
        precondition(archive.storePresets.count == 1)
        precondition(archive.shoppingList.count == 1)
        precondition(archive.pantryCount == 1)
        precondition(archive.products[0].photos[0].imageData == photoData)
        precondition(archive.products[0].brand == "測試品牌")
        precondition(archive.products[0].manufacturerName == "測試食品公司")
        precondition(archive.products[0].records.allSatisfy { $0.currencyCode == "USD" })
        precondition(archive.products[0].records.contains { $0.isGroupPackage == true && $0.groupContentCount == 4 })
        precondition(archive.products[0].records.allSatisfy { $0.recordStatus == PurchaseRecordStatus.complete.rawValue })
        precondition(archive.products[0].records.allSatisfy { $0.quantityWasEntered == true })
        precondition(product.latestRecord?.id == record.id)
        precondition(product.priceStatistics?.lowestRecord.id == record.id)
        precondition(product.priceStatistics?.highestRecord.id == previousRecord.id)

        let encoded = try BackupCoding.encoder.encode(archive)
        let decoded = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: encoded)
        try BackupManager.validate(decoded)

        var schema3Object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        schema3Object["schemaVersion"] = 3
        var schema3Products = schema3Object["products"] as! [[String: Any]]
        var schema3Records = schema3Products[0]["records"] as! [[String: Any]]
        for index in schema3Records.indices {
            schema3Records[index].removeValue(forKey: "recordStatus")
            schema3Records[index].removeValue(forKey: "quantityWasEntered")
            schema3Records[index].removeValue(forKey: "locationSource")
        }
        schema3Products[0]["records"] = schema3Records
        schema3Object["products"] = schema3Products
        let schema3Archive = try BackupCoding.decoder.decode(
            SnapsBackupArchive.self,
            from: JSONSerialization.data(withJSONObject: schema3Object)
        )
        try BackupManager.validate(schema3Archive)
        precondition(schema3Archive.products[0].records.allSatisfy { $0.recordStatus == nil })

        var envelope = SnapsSyncEnvelope.initial(archive: decoded, provider: .googleDrive)
        for _ in 0..<4 {
            envelope = envelope.updating(with: decoded, provider: .googleDrive)
        }
        precondition(envelope.history.count == 3)
        let envelopeData = try SyncCoding.encoder.encode(envelope)
        let decodedEnvelope = try SyncCoding.decoder.decode(SnapsSyncEnvelope.self, from: envelopeData)
        try SyncCoordinator.validate(decodedEnvelope)

        let syncFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapsShopListSyncSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: syncFolder) }
        let initiallyFoundURL = try SyncCoordinator.existingSyncFile(in: syncFolder)
        precondition(initiallyFoundURL == nil)
        let alternateURL = syncFolder.appendingPathComponent("Alternate.snapssync")
        try SyncCoordinator.write(decodedEnvelope, to: alternateURL)
        let alternateFoundURL = try SyncCoordinator.existingSyncFile(in: syncFolder)
        precondition(alternateFoundURL?.lastPathComponent == alternateURL.lastPathComponent)
        let preferredURL = SyncCoordinator.newSyncFileURL(in: syncFolder)
        try SyncCoordinator.write(decodedEnvelope, to: preferredURL)
        let preferredFoundURL = try SyncCoordinator.existingSyncFile(in: syncFolder)
        precondition(preferredFoundURL?.lastPathComponent == preferredURL.lastPathComponent)

        var legacyObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyObject["schemaVersion"] = 1
        legacyObject.removeValue(forKey: "pantryEntries")
        var legacyProducts = legacyObject["products"] as! [[String: Any]]
        legacyProducts[0].removeValue(forKey: "brand")
        legacyProducts[0].removeValue(forKey: "manufacturerName")
        var legacyRecords = legacyProducts[0]["records"] as! [[String: Any]]
        for index in legacyRecords.indices {
            legacyRecords[index].removeValue(forKey: "currencyCode")
            legacyRecords[index].removeValue(forKey: "isGroupPackage")
            legacyRecords[index].removeValue(forKey: "groupContentCount")
        }
        legacyProducts[0]["records"] = legacyRecords
        legacyObject["products"] = legacyProducts
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyArchive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: legacyData)
        try BackupManager.validate(legacyArchive)
        precondition(legacyArchive.products[0].brand == nil)
        precondition(legacyArchive.products[0].manufacturerName == nil)
        precondition(legacyArchive.products[0].records.allSatisfy { $0.currencyCode == nil })
        precondition(legacyArchive.products[0].records.allSatisfy { $0.isGroupPackage == nil })

        legacyObject["schemaVersion"] = 2
        let schema2Data = try JSONSerialization.data(withJSONObject: legacyObject)
        let schema2Archive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: schema2Data)
        try BackupManager.validate(schema2Archive)
        precondition(schema2Archive.pantryEntries == nil)

        let merge = try BackupManager.importArchive(decoded, mode: .merge, in: context)
        precondition(merge.products == 0)
        precondition(merge.records == 0)
        precondition(merge.photos == 0)
        precondition(merge.pantryEntries == 0)
        try expectCounts(context, products: 1, records: 2, photos: 1, stores: 1, shopping: 1, pantry: 1)

        var editedObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var editedProducts = editedObject["products"] as! [[String: Any]]
        editedProducts[0]["name"] = "桌機修改名稱"
        var editedRecords = editedProducts[0]["records"] as! [[String: Any]]
        editedRecords[0]["store"] = "桌機修改店家"
        editedProducts[0]["records"] = editedRecords
        editedObject["products"] = editedProducts
        let editedData = try JSONSerialization.data(withJSONObject: editedObject)
        let editedArchive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: editedData)
        _ = try BackupManager.importArchive(editedArchive, mode: .synchronize, in: context)
        precondition(product.name == "桌機修改名稱")
        precondition(product.records?.contains(where: { $0.store == "桌機修改店家" }) == true)

        // Legacy or interrupted imports can leave child rows without a product.
        // Clearing the database must remove these rows too.
        context.insert(PurchaseRecord(
            store: "孤立紀錄測試",
            price: 1,
            amount: 0,
            unit: "",
            isOnSale: false,
            isBuyOneGetOne: false
        ))
        context.insert(ProductPhoto(fileName: "", imageData: Data([0x00])))
        try context.save()
        try expectCounts(context, products: 1, records: 3, photos: 2, stores: 1, shopping: 1, pantry: 1)

        try BackupManager.deleteAll(in: context)
        try expectCounts(context, products: 0, records: 0, photos: 0, stores: 0, shopping: 0, pantry: 0)

        let restored = try BackupManager.importArchive(decoded, mode: .replace, in: context)
        precondition(restored.products == 1)
        precondition(restored.records == 2)
        precondition(restored.photos == 1)
        precondition(restored.pantryEntries == 1)
        try expectCounts(context, products: 1, records: 2, photos: 1, stores: 1, shopping: 1, pantry: 1)

        let restoredProduct = try context.fetch(FetchDescriptor<Product>()).first
        precondition(restoredProduct?.barcode == product.barcode)
        precondition(restoredProduct?.brand == "測試品牌")
        precondition(restoredProduct?.manufacturerName == "測試食品公司")
        precondition(restoredProduct?.records?.contains(where: { $0.storeBranch == "一號店" }) == true)
        precondition(restoredProduct?.records?.allSatisfy { $0.normalizedCurrencyCode == "USD" } == true)
        precondition(restoredProduct?.records?.contains { $0.isGroupPackage && $0.groupContentCount == 4 } == true)
        precondition(restoredProduct?.photos?.first?.imageData == photoData)
        precondition(restoredProduct?.currentPantryEntry?.purchasedAt == record.recordedAt)

        let retainedTWDRecord = PurchaseRecord(
            store: "台幣保留測試店",
            price: 50,
            currencyCode: SupportedCurrency.TWD.rawValue,
            amount: 1,
            unit: "件",
            isOnSale: false,
            isBuyOneGetOne: false,
            product: restoredProduct
        )
        context.insert(retainedTWDRecord)
        try context.save()
        let recordsBeforeForeignClear = try context.fetch(FetchDescriptor<PurchaseRecord>())
        let foreignRecords = recordsBeforeForeignClear.filter(\.isForeignCurrencyPurchase)
        precondition(foreignRecords.count == 2)
        foreignRecords.forEach(context.delete)
        try context.save()
        let recordsAfterForeignClear = try context.fetch(FetchDescriptor<PurchaseRecord>())
        precondition(recordsAfterForeignClear.contains(where: { $0.id == retainedTWDRecord.id }))
        precondition(recordsAfterForeignClear.allSatisfy { !$0.isForeignCurrencyPurchase })

        print("BackupSupport smoke tests passed")
    }

    private static func expectCounts(
        _ context: ModelContext,
        products: Int,
        records: Int,
        photos: Int,
        stores: Int,
        shopping: Int,
        pantry: Int
    ) throws {
        let productCount = try context.fetchCount(FetchDescriptor<Product>())
        let recordCount = try context.fetchCount(FetchDescriptor<PurchaseRecord>())
        let photoCount = try context.fetchCount(FetchDescriptor<ProductPhoto>())
        let storeCount = try context.fetchCount(FetchDescriptor<StorePreset>())
        let shoppingCount = try context.fetchCount(FetchDescriptor<ShoppingListItem>())
        let pantryCount = try context.fetchCount(FetchDescriptor<PantryEntry>())
        precondition(productCount == products)
        precondition(recordCount == records)
        precondition(photoCount == photos)
        precondition(storeCount == stores)
        precondition(shoppingCount == shopping)
        precondition(pantryCount == pantry)
    }
}
