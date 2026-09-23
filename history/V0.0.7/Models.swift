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
        (records ?? []).max { $0.recordedAt < $1.recordedAt }
    }

    var priceStatistics: ProductPriceStatistics? {
        ProductPriceStatistics(records: records ?? [])
    }
}

struct ProductPriceStatistics {
    let lowestRecord: PurchaseRecord
    let highestRecord: PurchaseRecord
    let averageEffectivePrice: Double
    let lowestNormalizedRecord: PurchaseRecord?
    let latestRecord: PurchaseRecord

    init?(records: [PurchaseRecord]) {
        let validRecords = records.filter { $0.price >= 0 && $0.price.isFinite }
        guard
            let lowest = validRecords.min(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice }),
            let highest = validRecords.max(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice })
        else { return nil }

        lowestRecord = lowest
        highestRecord = highest
        latestRecord = validRecords.max { $0.recordedAt < $1.recordedAt } ?? lowest
        averageEffectivePrice = validRecords.map(\.effectiveUnitPrice).reduce(0, +) / Double(validRecords.count)
        lowestNormalizedRecord = validRecords
            .filter { $0.pricePerHundred != nil }
            .min { ($0.pricePerHundred ?? .greatestFiniteMagnitude) < ($1.pricePerHundred ?? .greatestFiniteMagnitude) }
    }
}

extension PurchaseRecord {
    var effectiveUnitPrice: Double {
        PriceCalculator.effectiveUnitPrice(
            totalPrice: price,
            purchaseQuantity: purchaseQuantity,
            isBuyOneGetOne: isBuyOneGetOne
        )
    }

    var pricePerHundred: Double? {
        PriceCalculator.pricePerHundred(
            totalPrice: price,
            purchaseQuantity: purchaseQuantity,
            isBuyOneGetOne: isBuyOneGetOne,
            amount: amount,
            unit: unit
        )
    }

    var normalizedUnitLabel: String? {
        PriceCalculator.normalizedUnit(unit)
    }

    var storeDisplayName: String {
        guard !store.isEmpty else { return "未填寫" }
        return storeBranch.isEmpty ? store : "\(store) \(storeBranch)"
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
    var normalizedKey: String = ""
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
        self.normalizedKey = StoreIdentity.key(name: name, branch: branch, city: city, district: district)
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
