import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let snapsShopListBackup = UTType(filenameExtension: "snapsbackup", conformingTo: .json) ?? .json
}

struct SnapsBackupArchive: Codable {
    let schemaVersion: Int
    let appVersion: String
    let createdAt: Date
    let products: [ProductPayload]
    let storePresets: [StorePayload]
    let shoppingList: [ShoppingPayload]
    let pantryEntries: [PantryPayload]?

    struct ProductPayload: Codable {
        let id: UUID
        let barcode: String
        let name: String
        let brand: String?
        let manufacturerName: String?
        let createdAt: Date
        let records: [RecordPayload]
        let photos: [PhotoPayload]
    }

    struct RecordPayload: Codable {
        let id: UUID
        let recordedAt: Date
        let store: String
        let storeBranch: String
        let city: String
        let district: String
        let price: Double
        let currencyCode: String?
        let purchaseQuantity: Int
        let isGroupPackage: Bool?
        let groupContentCount: Int?
        let amount: Double
        let unit: String
        let isOnSale: Bool
        let isBuyOneGetOne: Bool
        let isDraft: Bool
        let recordStatus: String?
        let quantityWasEntered: Bool?
        let locationSource: String?
        let latitude: Double?
        let longitude: Double?
        let locationAccuracy: Double?
    }

    struct PhotoPayload: Codable {
        let id: UUID
        let createdAt: Date
        let imageData: Data?
    }

    struct StorePayload: Codable {
        let id: UUID
        let name: String
        let branch: String
        let city: String
        let district: String
        let lastUsedAt: Date
        let useCount: Int
    }

    struct ShoppingPayload: Codable {
        let id: UUID
        let productID: UUID
        let barcode: String
        let productName: String
        let currencyCode: String?
        let desiredQuantity: Int
        let addedAt: Date
    }

    struct PantryPayload: Codable {
        let id: UUID
        let productID: UUID
        let purchasedAt: Date
        let expirationDate: Date
        let usedUpAt: Date?
        let createdAt: Date
    }

    var recordCount: Int { products.reduce(0) { $0 + $1.records.count } }
    var photoCount: Int { products.reduce(0) { $0 + $1.photos.count } }
    var pantryCount: Int { pantryEntries?.count ?? 0 }
}

struct SnapsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.snapsShopListBackup, .json] }
    var archive: SnapsBackupArchive

    init(archive: SnapsBackupArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.unreadableFile
        }
        archive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: data)
        try BackupManager.validate(archive)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupCoding.encoder.encode(archive))
    }
}

enum BackupImportMode: Equatable {
    case merge
    case replace
    case synchronize
}

struct BackupImportSummary {
    let products: Int
    let records: Int
    let photos: Int
    let pantryEntries: Int
}

enum BackupError: LocalizedError {
    case unreadableFile
    case unsupportedSchema(Int)
    case invalidProduct
    case unknownRecordStatus(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "無法讀取備份檔。"
        case .unsupportedSchema(let version): "不支援備份格式版本 \(version)。"
        case .invalidProduct: "備份中包含無效的商品識別碼。"
        case .unknownRecordStatus(let status): "備份中包含未知的紀錄狀態 \(status)。"
        }
    }
}

enum BackupCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
enum BackupManager {
    private static func decodedRecordStatus(
        _ rawValue: String?,
        isDraft: Bool,
        schemaVersion: Int
    ) throws -> PurchaseRecordStatus {
        if let rawValue, let status = PurchaseRecordStatus(rawValue: rawValue) {
            return status
        }
        if schemaVersion >= 5, let rawValue, !rawValue.isEmpty {
            throw BackupError.unknownRecordStatus(rawValue)
        }
        return isDraft ? .quickDraft : .complete
    }

    private static func shoppingKey(barcode: String, currencyCode: String) -> String {
        "\(barcode)|\(SupportedCurrency.normalized(currencyCode).rawValue)"
    }

    static func makeArchive(in context: ModelContext, includePhotos: Bool = true) throws -> SnapsBackupArchive {
        let products = try context.fetch(FetchDescriptor<Product>()).map { product in
            SnapsBackupArchive.ProductPayload(
                id: product.id,
                barcode: product.barcode,
                name: product.name,
                brand: product.brand,
                manufacturerName: product.manufacturerName,
                createdAt: product.createdAt,
                records: (product.records ?? []).map { record in
                    .init(
                        id: record.id,
                        recordedAt: record.recordedAt,
                        store: record.store,
                        storeBranch: record.storeBranch,
                        city: record.city,
                        district: record.district,
                        price: record.price,
                        currencyCode: record.normalizedCurrencyCode,
                        purchaseQuantity: record.purchaseQuantity,
                        isGroupPackage: record.isGroupPackage,
                        groupContentCount: record.groupContentCount,
                        amount: record.amount,
                        unit: record.unit,
                        isOnSale: record.isOnSale,
                        isBuyOneGetOne: record.isBuyOneGetOne,
                        isDraft: record.isDraft,
                        recordStatus: record.recordStatus.rawValue,
                        quantityWasEntered: record.quantityWasEntered,
                        locationSource: record.locationSource.rawValue,
                        latitude: record.latitude,
                        longitude: record.longitude,
                        locationAccuracy: record.locationAccuracy
                    )
                },
                photos: (includePhotos ? product.sortedPhotos : []).map { photo in
                    .init(id: photo.id, createdAt: photo.createdAt, imageData: photo.imageData)
                }
            )
        }

        let stores = try context.fetch(FetchDescriptor<StorePreset>()).map {
            SnapsBackupArchive.StorePayload(
                id: $0.id,
                name: $0.name,
                branch: $0.branch,
                city: $0.city,
                district: $0.district,
                lastUsedAt: $0.lastUsedAt,
                useCount: $0.useCount
            )
        }

        let shopping = try context.fetch(FetchDescriptor<ShoppingListItem>()).map {
            SnapsBackupArchive.ShoppingPayload(
                id: $0.id,
                productID: $0.productID,
                barcode: $0.barcode,
                productName: $0.productName,
                currencyCode: $0.currencyCode,
                desiredQuantity: $0.desiredQuantity,
                addedAt: $0.addedAt
            )
        }

        let pantry: [SnapsBackupArchive.PantryPayload] = try context
            .fetch(FetchDescriptor<PantryEntry>())
            .compactMap { entry -> SnapsBackupArchive.PantryPayload? in
            guard let productID = entry.product?.id else { return nil }
            return SnapsBackupArchive.PantryPayload(
                id: entry.id,
                productID: productID,
                purchasedAt: entry.purchasedAt,
                expirationDate: entry.expirationDate,
                usedUpAt: entry.usedUpAt,
                createdAt: entry.createdAt
            )
        }

        return SnapsBackupArchive(
            schemaVersion: 5,
            appVersion: AppTheme.version,
            createdAt: .now,
            products: products,
            storePresets: stores,
            shoppingList: shopping,
            pantryEntries: pantry
        )
    }

    nonisolated static func validate(_ archive: SnapsBackupArchive) throws {
        guard (1...5).contains(archive.schemaVersion) else {
            throw BackupError.unsupportedSchema(archive.schemaVersion)
        }
        guard archive.products.allSatisfy({ !$0.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw BackupError.invalidProduct
        }
    }

    static func importArchive(
        _ archive: SnapsBackupArchive,
        mode: BackupImportMode,
        in context: ModelContext
    ) throws -> BackupImportSummary {
        try validate(archive)
        if mode == .replace { try deleteAll(in: context, save: false) }

        let currentProducts = mode == .replace ? [] : try context.fetch(FetchDescriptor<Product>())
        var productsByBarcode = Dictionary(
            currentProducts.map { ($0.barcode, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentRecords = mode == .replace ? [] : try context.fetch(FetchDescriptor<PurchaseRecord>())
        let currentPhotos = mode == .replace ? [] : try context.fetch(FetchDescriptor<ProductPhoto>())
        var recordsByID = Dictionary(uniqueKeysWithValues: currentRecords.map { ($0.id, $0) })
        var photosByID = Dictionary(uniqueKeysWithValues: currentPhotos.map { ($0.id, $0) })
        var productIDMap: [UUID: UUID] = [:]
        var importedProducts = 0
        var importedRecords = 0
        var importedPhotos = 0
        var importedPantryEntries = 0

        for payload in archive.products {
            let product: Product
            if let existing = productsByBarcode[payload.barcode] {
                product = existing
                if mode == .synchronize {
                    product.name = payload.name
                    product.brand = payload.brand ?? ""
                    product.manufacturerName = payload.manufacturerName ?? ""
                    product.createdAt = payload.createdAt
                } else {
                    if product.name.isEmpty { product.name = payload.name }
                    if product.brand.isEmpty { product.brand = payload.brand ?? "" }
                    if product.manufacturerName.isEmpty {
                        product.manufacturerName = payload.manufacturerName ?? ""
                    }
                }
            } else {
                product = Product(
                    barcode: payload.barcode,
                    name: payload.name,
                    brand: payload.brand ?? "",
                    manufacturerName: payload.manufacturerName ?? "",
                    createdAt: payload.createdAt
                )
                product.id = payload.id
                context.insert(product)
                productsByBarcode[payload.barcode] = product
                importedProducts += 1
            }
            productIDMap[payload.id] = product.id

            for item in payload.records {
                if let record = recordsByID[item.id] {
                    guard mode == .synchronize else { continue }
                    record.recordedAt = item.recordedAt
                    record.store = item.store
                    record.storeBranch = item.storeBranch
                    record.city = item.city
                    record.district = item.district
                    record.price = item.price
                    record.currencyCode = SupportedCurrency.normalized(
                        item.currencyCode ?? SupportedCurrency.TWD.rawValue
                    ).rawValue
                    record.purchaseQuantity = max(1, item.purchaseQuantity)
                    record.isGroupPackage = item.isGroupPackage ?? false
                    record.groupContentCount = max(1, item.groupContentCount ?? 1)
                    record.amount = item.amount
                    record.unit = item.unit
                    record.isOnSale = item.isOnSale
                    record.isBuyOneGetOne = item.isBuyOneGetOne
                    record.isDraft = item.isDraft
                    record.recordStatus = try decodedRecordStatus(item.recordStatus, isDraft: item.isDraft, schemaVersion: archive.schemaVersion)
                    record.quantityWasEntered = item.quantityWasEntered ?? true
                    record.locationSource = PurchaseLocationSource(rawValue: item.locationSource ?? "")
                        ?? ((item.latitude == nil || item.longitude == nil) ? .none : .liveGPS)
                    record.latitude = item.latitude
                    record.longitude = item.longitude
                    record.locationAccuracy = item.locationAccuracy
                    record.product = product
                    continue
                }
                let record = PurchaseRecord(
                    recordedAt: item.recordedAt,
                    store: item.store,
                    storeBranch: item.storeBranch,
                    city: item.city,
                    district: item.district,
                    price: item.price,
                    currencyCode: item.currencyCode ?? SupportedCurrency.TWD.rawValue,
                    amount: item.amount,
                    unit: item.unit,
                    isOnSale: item.isOnSale,
                    isBuyOneGetOne: item.isBuyOneGetOne,
                    isDraft: item.isDraft,
                    purchaseQuantity: item.purchaseQuantity,
                    isGroupPackage: item.isGroupPackage ?? false,
                    groupContentCount: item.groupContentCount ?? 1,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    locationAccuracy: item.locationAccuracy,
                    product: product,
                    recordStatus: try decodedRecordStatus(item.recordStatus, isDraft: item.isDraft, schemaVersion: archive.schemaVersion),
                    quantityWasEntered: item.quantityWasEntered ?? true,
                    locationSource: PurchaseLocationSource(rawValue: item.locationSource ?? "")
                        ?? ((item.latitude == nil || item.longitude == nil) ? .none : .liveGPS)
                )
                record.id = item.id
                context.insert(record)
                recordsByID[item.id] = record
                importedRecords += 1
            }

            for item in payload.photos {
                if let photo = photosByID[item.id] {
                    guard mode == .synchronize else { continue }
                    photo.createdAt = item.createdAt
                    if let imageData = item.imageData { photo.imageData = imageData }
                    photo.product = product
                    continue
                }
                let photo = ProductPhoto(
                    fileName: "",
                    imageData: item.imageData,
                    createdAt: item.createdAt,
                    product: product
                )
                photo.id = item.id
                context.insert(photo)
                photosByID[item.id] = photo
                importedPhotos += 1
            }
        }

        let currentStores = mode == .replace ? [] : try context.fetch(FetchDescriptor<StorePreset>())
        var storesByID = Dictionary(uniqueKeysWithValues: currentStores.map { ($0.id, $0) })
        var storesByKey = Dictionary(
            currentStores.map { ($0.normalizedKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for item in archive.storePresets {
            let key = StoreIdentity.key(name: item.name, branch: item.branch, city: item.city, district: item.district)
            if let preset = storesByID[item.id] ?? storesByKey[key] {
                guard mode == .synchronize else { continue }
                preset.name = item.name
                preset.branch = item.branch
                preset.city = item.city
                preset.district = item.district
                preset.normalizedKey = key
                preset.lastUsedAt = item.lastUsedAt
                preset.useCount = item.useCount
                continue
            }
            let preset = StorePreset(
                name: item.name,
                branch: item.branch,
                city: item.city,
                district: item.district,
                lastUsedAt: item.lastUsedAt,
                useCount: item.useCount
            )
            preset.id = item.id
            context.insert(preset)
            storesByID[item.id] = preset
            storesByKey[key] = preset
        }

        let currentShopping = mode == .replace ? [] : try context.fetch(FetchDescriptor<ShoppingListItem>())
        var shoppingByID = Dictionary(uniqueKeysWithValues: currentShopping.map { ($0.id, $0) })
        var shoppingByKey = Dictionary(
            currentShopping.map { (shoppingKey(barcode: $0.barcode, currencyCode: $0.currencyCode), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for item in archive.shoppingList {
            let currencyCode = SupportedCurrency.normalized(item.currencyCode ?? SupportedCurrency.TWD.rawValue).rawValue
            let key = shoppingKey(barcode: item.barcode, currencyCode: currencyCode)
            if let listItem = shoppingByID[item.id] ?? shoppingByKey[key] {
                guard mode == .synchronize else { continue }
                listItem.productID = productIDMap[item.productID] ?? item.productID
                listItem.barcode = item.barcode
                listItem.productName = item.productName
                listItem.currencyCode = currencyCode
                listItem.desiredQuantity = max(1, item.desiredQuantity)
                listItem.addedAt = item.addedAt
                continue
            }
            let listItem = ShoppingListItem(
                productID: productIDMap[item.productID] ?? item.productID,
                barcode: item.barcode,
                productName: item.productName,
                currencyCode: currencyCode,
                desiredQuantity: max(1, item.desiredQuantity),
                addedAt: item.addedAt
            )
            listItem.id = item.id
            context.insert(listItem)
            shoppingByID[item.id] = listItem
            shoppingByKey[key] = listItem
        }

        let currentPantry = mode == .replace ? [] : try context.fetch(FetchDescriptor<PantryEntry>())
        var pantryByID = Dictionary(uniqueKeysWithValues: currentPantry.map { ($0.id, $0) })
        let productsByID = Dictionary(
            productsByBarcode.values.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for item in archive.pantryEntries ?? [] {
            guard let product = productsByID[productIDMap[item.productID] ?? item.productID] else { continue }
            if let entry = pantryByID[item.id] {
                guard mode == .synchronize else { continue }
                entry.purchasedAt = item.purchasedAt
                entry.expirationDate = item.expirationDate
                entry.usedUpAt = item.usedUpAt
                entry.createdAt = item.createdAt
                entry.product = product
                continue
            }
            let entry = PantryEntry(
                purchasedAt: item.purchasedAt,
                expirationDate: item.expirationDate,
                usedUpAt: item.usedUpAt,
                createdAt: item.createdAt,
                product: product
            )
            entry.id = item.id
            context.insert(entry)
            pantryByID[item.id] = entry
            importedPantryEntries += 1
        }

        try context.save()
        return BackupImportSummary(
            products: importedProducts,
            records: importedRecords,
            photos: importedPhotos,
            pantryEntries: importedPantryEntries
        )
    }

    static func deleteAll(in context: ModelContext, save: Bool = true) throws {
        try context.fetch(FetchDescriptor<ShoppingListItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StorePreset>()).forEach(context.delete)
        // Explicitly delete children as well as products. This also clears legacy
        // or partially imported rows whose relationship is unexpectedly missing.
        try context.fetch(FetchDescriptor<PurchaseRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ProductPhoto>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<PantryEntry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Product>()).forEach(context.delete)
        if save { try context.save() }
    }
}
