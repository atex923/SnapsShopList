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
    var price: Double = 0
    var amount: Double = 0
    var unit: String = ""
    var isOnSale: Bool = false
    var isBuyOneGetOne: Bool = false
    var product: Product?

    init(
        recordedAt: Date = .now,
        store: String,
        price: Double,
        amount: Double,
        unit: String,
        isOnSale: Bool,
        isBuyOneGetOne: Bool,
        product: Product? = nil
    ) {
        self.recordedAt = recordedAt
        self.store = store
        self.price = price
        self.amount = amount
        self.unit = unit
        self.isOnSale = isOnSale
        self.isBuyOneGetOne = isBuyOneGetOne
        self.product = product
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
