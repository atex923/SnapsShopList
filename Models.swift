import Foundation
import SwiftData

enum ProductIdentifier {
    static let manualPrefix = "MANUAL-"

    static func makeManual() -> String {
        manualPrefix + UUID().uuidString
    }

    static func isManual(_ value: String) -> Bool {
        value.hasPrefix(manualPrefix)
    }
}

@Model
final class Product {
    var id: UUID = UUID()
    var barcode: String = ""
    var name: String = ""
    var brand: String = ""
    var manufacturerName: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PurchaseRecord.product)
    var records: [PurchaseRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProductPhoto.product)
    var photos: [ProductPhoto]? = []

    @Relationship(deleteRule: .cascade, inverse: \PantryEntry.product)
    var pantryEntries: [PantryEntry]? = []

    init(
        barcode: String,
        name: String,
        brand: String = "",
        manufacturerName: String = "",
        createdAt: Date = .now
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.manufacturerName = manufacturerName
        self.createdAt = createdAt
    }

    var sortedRecords: [PurchaseRecord] {
        (records ?? []).sorted { $0.recordedAt > $1.recordedAt }
    }

    var sortedPhotos: [ProductPhoto] {
        (photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var latestRecord: PurchaseRecord? {
        latestPurchaseRecord
    }

    var latestPurchaseRecord: PurchaseRecord? {
        (records ?? [])
            .filter { $0.recordStatus == .complete }
            .max { $0.recordedAt < $1.recordedAt }
    }

    var latestPriceObservation: PurchaseRecord? {
        comparisonRecords.max { $0.recordedAt < $1.recordedAt }
    }

    var comparisonRecords: [PurchaseRecord] {
        (records ?? []).filter { $0.recordStatus != .quickDraft }
    }

    var sortedPantryEntries: [PantryEntry] {
        (pantryEntries ?? []).sorted { $0.purchasedAt > $1.purchasedAt }
    }

    var currentPantryEntry: PantryEntry? {
        sortedPantryEntries.first { $0.usedUpAt == nil }
    }

    var priceStatistics: ProductPriceStatistics? {
        guard let currencyCode = latestPriceObservation?.normalizedCurrencyCode else { return nil }
        return ProductPriceStatistics(records: comparisonRecords, currencyCode: currencyCode)
    }

    func priceStatistics(currencyCode: String) -> ProductPriceStatistics? {
        ProductPriceStatistics(records: comparisonRecords, currencyCode: currencyCode)
    }

    var isManualProduct: Bool {
        ProductIdentifier.isManual(barcode)
    }

    var barcodeDisplayText: String {
        isManualProduct ? "無條碼" : barcode
    }
}

struct ProductPriceStatistics {
    let currencyCode: String
    let lowestRecord: PurchaseRecord
    let highestRecord: PurchaseRecord
    let averageEffectivePrice: Double
    let lowestNormalizedRecord: PurchaseRecord?
    let latestRecord: PurchaseRecord

    init?(records: [PurchaseRecord], currencyCode: String) {
        let normalizedCurrencyCode = SupportedCurrency.normalized(currencyCode).rawValue
        let validRecords = records.filter {
            $0.price >= 0
                && $0.price.isFinite
                && $0.quantityWasEntered
                && $0.normalizedCurrencyCode == normalizedCurrencyCode
        }
        guard
            let lowest = validRecords.min(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice }),
            let highest = validRecords.max(by: { $0.effectiveUnitPrice < $1.effectiveUnitPrice })
        else { return nil }

        self.currencyCode = normalizedCurrencyCode
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
    var recordStatus: PurchaseRecordStatus {
        get { PurchaseRecordStatus(rawValue: recordStatusRaw) ?? (isDraft ? .quickDraft : .comparison) }
        set { recordStatusRaw = newValue.rawValue }
    }

    var locationSource: PurchaseLocationSource {
        get { PurchaseLocationSource(rawValue: locationSourceRaw) ?? ((latitude == nil || longitude == nil) ? .none : .liveGPS) }
        set { locationSourceRaw = newValue.rawValue }
    }

    var isUnitPriceComparable: Bool { quantityWasEntered }

    var effectiveUnitPrice: Double {
        PriceCalculator.effectiveUnitPrice(
            totalPrice: price,
            purchaseQuantity: purchaseQuantity,
            isBuyOneGetOne: isBuyOneGetOne,
            groupContentCount: groupContentCount
        )
    }

    var pricePerHundred: Double? {
        PriceCalculator.pricePerHundred(
            totalPrice: price,
            purchaseQuantity: purchaseQuantity,
            isBuyOneGetOne: isBuyOneGetOne,
            groupContentCount: groupContentCount,
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

    var normalizedCurrencyCode: String {
        SupportedCurrency.normalized(currencyCode).rawValue
    }

    var isForeignCurrencyPurchase: Bool {
        normalizedCurrencyCode != SupportedCurrency.TWD.rawValue
    }

    var formattedPrice: String {
        SupportedCurrency.format(price, code: normalizedCurrencyCode)
    }

    var formattedEffectiveUnitPrice: String {
        quantityWasEntered
            ? SupportedCurrency.format(effectiveUnitPrice, code: normalizedCurrencyCode)
            : "數量未填"
    }

    var formattedPricePerHundred: String? {
        pricePerHundred.map { SupportedCurrency.format($0, code: normalizedCurrencyCode) }
    }

    var referenceUnitPrice: (value: Double, label: String)? {
        PriceCalculator.referenceUnitPrice(
            totalPrice: price,
            purchaseQuantity: purchaseQuantity,
            isBuyOneGetOne: isBuyOneGetOne,
            groupContentCount: groupContentCount,
            amount: amount,
            unit: unit
        )
    }

}

enum ProductSimilarity {
    static func related(to product: Product, among products: [Product], limit: Int = 5) -> [Product] {
        let source = normalized(product.name)
        guard source.count >= 2 else { return [] }
        return products
            .filter { $0.id != product.id && score(source, normalized($0.name)) != nil }
            .sorted {
                let left = score(source, normalized($0.name)) ?? .greatestFiniteMagnitude
                let right = score(source, normalized($1.name)) ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                return ($0.latestRecord?.recordedAt ?? $0.createdAt) > ($1.latestRecord?.recordedAt ?? $1.createdAt)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(_ source: String, _ candidate: String) -> Double? {
        guard candidate.count >= 2 else { return nil }
        if source == candidate { return 0 }
        if source.contains(candidate) || candidate.contains(source) { return 1 }
        let sourcePairs = pairs(source)
        let candidatePairs = pairs(candidate)
        guard !sourcePairs.isEmpty, !candidatePairs.isEmpty else { return nil }
        let overlap = sourcePairs.intersection(candidatePairs).count
        let similarity = Double(overlap * 2) / Double(sourcePairs.count + candidatePairs.count)
        return similarity >= 0.45 ? 2 - similarity : nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func pairs(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }
        return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
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
    var currencyCode: String = SupportedCurrency.TWD.rawValue
    var purchaseQuantity: Int = 1
    var isGroupPackage: Bool = false
    var groupContentCount: Int = 1
    var amount: Double = 0
    var unit: String = ""
    var isOnSale: Bool = false
    var isBuyOneGetOne: Bool = false
    var isDraft: Bool = false
    var recordStatusRaw: String = PurchaseRecordStatus.complete.rawValue
    var quantityWasEntered: Bool = true
    var locationSourceRaw: String = PurchaseLocationSource.none.rawValue
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
        currencyCode: String = SupportedCurrency.TWD.rawValue,
        amount: Double,
        unit: String,
        isOnSale: Bool,
        isBuyOneGetOne: Bool,
        isDraft: Bool = false,
        purchaseQuantity: Int = 1,
        isGroupPackage: Bool = false,
        groupContentCount: Int = 1,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracy: Double? = nil,
        product: Product? = nil,
        recordStatus: PurchaseRecordStatus = .complete,
        quantityWasEntered: Bool = true,
        locationSource: PurchaseLocationSource = .none
    ) {
        self.recordedAt = recordedAt
        self.store = store
        self.storeBranch = storeBranch
        self.city = city
        self.district = district
        self.price = price
        self.currencyCode = SupportedCurrency.normalized(currencyCode).rawValue
        self.amount = amount
        self.unit = unit
        self.isOnSale = isOnSale
        self.isBuyOneGetOne = isBuyOneGetOne
        self.isDraft = isDraft
        self.recordStatusRaw = recordStatus.rawValue
        self.quantityWasEntered = quantityWasEntered
        self.locationSourceRaw = locationSource.rawValue
        self.purchaseQuantity = purchaseQuantity
        self.isGroupPackage = isGroupPackage
        self.groupContentCount = max(1, groupContentCount)
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
    var currencyCode: String = SupportedCurrency.TWD.rawValue
    var desiredQuantity: Int = 1
    var addedAt: Date = Date()

    init(
        productID: UUID,
        barcode: String,
        productName: String,
        currencyCode: String = SupportedCurrency.TWD.rawValue,
        desiredQuantity: Int = 1,
        addedAt: Date = .now
    ) {
        self.productID = productID
        self.barcode = barcode
        self.productName = productName
        self.currencyCode = SupportedCurrency.normalized(currencyCode).rawValue
        self.desiredQuantity = desiredQuantity
        self.addedAt = addedAt
    }
}

@Model
final class PantryEntry {
    var id: UUID = UUID()
    var purchasedAt: Date = Date()
    var expirationDate: Date = Date()
    var usedUpAt: Date?
    var createdAt: Date = Date()
    var product: Product?

    init(
        purchasedAt: Date = .now,
        expirationDate: Date = .now,
        usedUpAt: Date? = nil,
        createdAt: Date = .now,
        product: Product? = nil
    ) {
        self.purchasedAt = purchasedAt
        self.expirationDate = expirationDate
        self.usedUpAt = usedUpAt
        self.createdAt = createdAt
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

enum PantryProductOrdering {
    static func precedes(_ left: Product, _ right: Product) -> Bool {
        let leftGroup = group(for: left)
        let rightGroup = group(for: right)
        if leftGroup != rightGroup {
            return leftGroup < rightGroup
        }

        let leftPantryDate = left.sortedPantryEntries.first?.purchasedAt
        let rightPantryDate = right.sortedPantryEntries.first?.purchasedAt
        if leftPantryDate != rightPantryDate {
            return (leftPantryDate ?? .distantPast) > (rightPantryDate ?? .distantPast)
        }

        let leftDate = left.latestRecord?.recordedAt ?? left.createdAt
        let rightDate = right.latestRecord?.recordedAt ?? right.createdAt
        if leftDate != rightDate { return leftDate > rightDate }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private static func group(for product: Product) -> Int {
        if product.currentPantryEntry != nil { return 0 }
        if !(product.pantryEntries ?? []).isEmpty { return 1 }
        return 2
    }
}

enum PantryHomeStatus: Equatable {
    case inStock
    case usedUp

    static func status(for product: Product?) -> PantryHomeStatus? {
        guard let product, !(product.pantryEntries ?? []).isEmpty else { return nil }
        return product.currentPantryEntry == nil ? .usedUp : .inStock
    }
}
