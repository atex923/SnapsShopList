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
        let amount: Double
        let unit: String
        let isOnSale: Bool
        let isBuyOneGetOne: Bool
        let isDraft: Bool
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
        let desiredQuantity: Int
        let addedAt: Date
    }

    var recordCount: Int { products.reduce(0) { $0 + $1.records.count } }
    var photoCount: Int { products.reduce(0) { $0 + $1.photos.count } }
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
}

struct BackupImportSummary {
    let products: Int
    let records: Int
    let photos: Int
}

enum BackupError: LocalizedError {
    case unreadableFile
    case unsupportedSchema(Int)
    case invalidProduct

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "無法讀取備份檔。"
        case .unsupportedSchema(let version): "不支援備份格式版本 \(version)。"
        case .invalidProduct: "備份中包含無效的商品識別碼。"
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
    static func makeArchive(in context: ModelContext) throws -> SnapsBackupArchive {
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
                        amount: record.amount,
                        unit: record.unit,
                        isOnSale: record.isOnSale,
                        isBuyOneGetOne: record.isBuyOneGetOne,
                        isDraft: record.isDraft,
                        latitude: record.latitude,
                        longitude: record.longitude,
                        locationAccuracy: record.locationAccuracy
                    )
                },
                photos: product.sortedPhotos.map { photo in
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
                desiredQuantity: $0.desiredQuantity,
                addedAt: $0.addedAt
            )
        }

        return SnapsBackupArchive(
            schemaVersion: 2,
            appVersion: AppTheme.version,
            createdAt: .now,
            products: products,
            storePresets: stores,
            shoppingList: shopping
        )
    }

    nonisolated static func validate(_ archive: SnapsBackupArchive) throws {
        guard (1...2).contains(archive.schemaVersion) else {
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
        var recordIDs = mode == .replace
            ? Set<UUID>()
            : Set(try context.fetch(FetchDescriptor<PurchaseRecord>()).map(\.id))
        var photoIDs = mode == .replace
            ? Set<UUID>()
            : Set(try context.fetch(FetchDescriptor<ProductPhoto>()).map(\.id))
        var productIDMap: [UUID: UUID] = [:]
        var importedProducts = 0
        var importedRecords = 0
        var importedPhotos = 0

        for payload in archive.products {
            let product: Product
            if let existing = productsByBarcode[payload.barcode] {
                product = existing
                if product.name.isEmpty { product.name = payload.name }
                if product.brand.isEmpty { product.brand = payload.brand ?? "" }
                if product.manufacturerName.isEmpty {
                    product.manufacturerName = payload.manufacturerName ?? ""
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

            for item in payload.records where recordIDs.insert(item.id).inserted {
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
                    latitude: item.latitude,
                    longitude: item.longitude,
                    locationAccuracy: item.locationAccuracy,
                    product: product
                )
                record.id = item.id
                context.insert(record)
                importedRecords += 1
            }

            for item in payload.photos where photoIDs.insert(item.id).inserted {
                let photo = ProductPhoto(
                    fileName: "",
                    imageData: item.imageData,
                    createdAt: item.createdAt,
                    product: product
                )
                photo.id = item.id
                context.insert(photo)
                importedPhotos += 1
            }
        }

        var storeKeys = mode == .replace
            ? Set<String>()
            : Set(try context.fetch(FetchDescriptor<StorePreset>()).map(\.normalizedKey))
        for item in archive.storePresets {
            let key = StoreIdentity.key(name: item.name, branch: item.branch, city: item.city, district: item.district)
            guard storeKeys.insert(key).inserted else { continue }
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
        }

        var shoppingBarcodes = mode == .replace
            ? Set<String>()
            : Set(try context.fetch(FetchDescriptor<ShoppingListItem>()).map(\.barcode))
        for item in archive.shoppingList where shoppingBarcodes.insert(item.barcode).inserted {
            let listItem = ShoppingListItem(
                productID: productIDMap[item.productID] ?? item.productID,
                barcode: item.barcode,
                productName: item.productName,
                desiredQuantity: max(1, item.desiredQuantity),
                addedAt: item.addedAt
            )
            listItem.id = item.id
            context.insert(listItem)
        }

        try context.save()
        return BackupImportSummary(
            products: importedProducts,
            records: importedRecords,
            photos: importedPhotos
        )
    }

    static func deleteAll(in context: ModelContext, save: Bool = true) throws {
        try context.fetch(FetchDescriptor<ShoppingListItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StorePreset>()).forEach(context.delete)
        // Explicitly delete children as well as products. This also clears legacy
        // or partially imported rows whose relationship is unexpectedly missing.
        try context.fetch(FetchDescriptor<PurchaseRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ProductPhoto>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Product>()).forEach(context.delete)
        if save { try context.save() }
    }
}
