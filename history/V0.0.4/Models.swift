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
