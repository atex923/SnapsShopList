import Foundation
import SwiftData

@Model
final class Product {
    var id: UUID = UUID()
    var barcode: String = ""
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PurchaseRecord.product)
    var records: [PurchaseRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProductPhoto.product)
    var photos: [ProductPhoto]? = []

    init(barcode: String, name: String, createdAt: Date = .now) {
        self.barcode = barcode
        self.name = name
        self.createdAt = createdAt
    }

    var sortedRecords: [PurchaseRecord] {
        (records ?? []).sorted { $0.recordedAt > $1.recordedAt }
    }

    var sortedPhotos: [ProductPhoto] {
        (photos ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var latestRecord: PurchaseRecord? {
        sortedRecords.first
    }

    var priceStatistics: ProductPriceStatistics? {
        ProductPriceStatistics(records: sortedRecords)
    }
}

struct ProductPriceStatistics {
    let lowestRecord: PurchaseRecord
    let highestRecord: PurchaseRecord
    let averageEffectivePrice: Double
    let lowestNormalizedRecord: PurchaseRecord?

    init?(records: [PurchaseRecord]) {
        let validRecords = records.filter { $0.price >= 0 && $0.price.isFinite }
        guard
            let lowest = validRecords.min(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice }),
            let highest = validRecords.max(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice })
        else { return nil }

        lowestRecord = lowest
        highestRecord = highest
        averageEffectivePrice = validRecords.map(\.effectiveUnitPrice).reduce(0, +) / Double(validRecords.count)
        lowestNormalizedRecord = validRecords
            .filter { $0.pricePerHundred != nil }
            .min { ($0.pricePerHundred ?? .greatestFiniteMagnitude) < ($1.pricePerHundred ?? .greatestFiniteMagnitude) }
    }
}

extension PurchaseRecord {
    var effectiveUnitPrice: Double {
        let purchasedUnits = Double(max(1, purchaseQuantity))
        let receivedUnits = isBuyOneGetOne ? purchasedUnits * 2 : purchasedUnits
        return price / receivedUnits
    }

    var pricePerHundred: Double? {
        guard let normalizedAmount, normalizedAmount > 0 else { return nil }
        return effectiveUnitPrice / normalizedAmount * 100
    }

    var normalizedUnitLabel: String? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "g", "克", "kg", "公斤": "g"
        case "ml", "毫升", "cc", "l", "公升": "ml"
        default: nil
        }
    }

    var storeDisplayName: String {
        guard !store.isEmpty else { return "未填寫" }
        return storeBranch.isEmpty ? store : "\(store) \(storeBranch)"
    }

    private var normalizedAmount: Double? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "g", "克", "ml", "毫升", "cc": amount
        case "kg", "公斤", "l", "公升": amount * 1_000
        default: nil
        }
    }
}

@Model
final class PurchaseRecord {
    var id: UUID = UUID()
    var recordedAt: Date = Date()
    var store: String = ""
    var storeBranch: String = ""
    var city: String = ""
    var district: String = ""
    var price: Double = 0
    var purchaseQuantity: Int = 1
    var amount: Double = 0
    var unit: String = ""
    var isOnSale: Bool = false
    var isBuyOneGetOne: Bool = false
    var latitude: Double?
    var longitude: Double?
    var locationAccuracy: Double?
    var product: Product?

    init(
        recordedAt: Date = .now,
        store: String,
        storeBranch: String = "",
        city: String = "",
        district: String = "",
        price: Double,
        amount: Double,
        unit: String,
        isOnSale: Bool,
        isBuyOneGetOne: Bool,
        purchaseQuantity: Int = 1,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracy: Double? = nil,
        product: Product? = nil
    ) {
        self.recordedAt = recordedAt
        self.store = store
        self.storeBranch = storeBranch
        self.city = city
        self.district = district
        self.price = price
        self.amount = amount
        self.unit = unit
        self.isOnSale = isOnSale
        self.isBuyOneGetOne = isBuyOneGetOne
        self.purchaseQuantity = purchaseQuantity
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracy = locationAccuracy
        self.product = product
    }
}

@Model
final class StorePreset {
    var id: UUID = UUID()
    var name: String = ""
    var branch: String = ""
    var city: String = ""
    var district: String = ""
    var lastUsedAt: Date = Date()
    var useCount: Int = 0

    init(
        name: String,
        branch: String = "",
        city: String = "",
        district: String = "",
        lastUsedAt: Date = .now,
        useCount: Int = 1
    ) {
        self.name = name
        self.branch = branch
        self.city = city
        self.district = district
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    var displayName: String {
        let location = [city, district].filter { !$0.isEmpty }.joined(separator: " ")
        let storeName = branch.isEmpty ? name : "\(name) \(branch)"
        return location.isEmpty ? storeName : "\(storeName)・\(location)"
    }
}

@Model
final class ShoppingListItem {
    var id: UUID = UUID()
    var productID: UUID = UUID()
    var barcode: String = ""
    var productName: String = ""
    var desiredQuantity: Int = 1
    var addedAt: Date = Date()

    init(
        productID: UUID,
        barcode: String,
        productName: String,
        desiredQuantity: Int = 1,
        addedAt: Date = .now
    ) {
        self.productID = productID
        self.barcode = barcode
        self.productName = productName
        self.desiredQuantity = desiredQuantity
        self.addedAt = addedAt
    }
}

@Model
final class ProductPhoto {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var fileName: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    var product: Product?

    init(
        fileName: String,
        imageData: Data? = nil,
        createdAt: Date = .now,
        product: Product? = nil
    ) {
        self.fileName = fileName
        self.imageData = imageData
        self.createdAt = createdAt
        self.product = product
    }
}
