import Foundation

enum SupportedCurrency: String, CaseIterable, Identifiable, Codable {
    case TWD
    case JPY
    case KRW
    case USD
    case EUR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .TWD: "台幣（NT$）"
        case .JPY: "日圓（¥）"
        case .KRW: "韓元（₩）"
        case .USD: "美金（US$）"
        case .EUR: "歐元（€）"
        }
    }

    var symbol: String {
        switch self {
        case .TWD: "NT$"
        case .JPY: "¥"
        case .KRW: "₩"
        case .USD: "US$"
        case .EUR: "€"
        }
    }

    var usesWholeUnits: Bool { self == .JPY || self == .KRW }

    func format(_ value: Double) -> String {
        let number = usesWholeUnits
            ? value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
            : value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
        return "\(symbol)\(number)"
    }

    static func normalized(_ code: String) -> Self {
        Self(rawValue: code.uppercased()) ?? .TWD
    }

    static func format(_ value: Double, code: String) -> String {
        normalized(code).format(value)
    }
}

struct PurchaseDraft: Equatable {
    var productName = ""
    var store = ""
    var amountText = ""
    var unit = ""
    var priceText = ""
    var purchaseQuantityText = "1"
}

struct ValidatedPurchase: Equatable {
    let amount: Double
    let price: Double
    let purchaseQuantity: Int
}

enum PurchaseValidator {
    static func validate(_ draft: PurchaseDraft, requiresProductName: Bool) -> ValidatedPurchase? {
        if requiresProductName && draft.productName.trimmed.isEmpty { return nil }
        let amount: Double
        if draft.amountText.trimmed.isEmpty {
            amount = 0
        } else if let parsedAmount = LocalizedNumberParser.double(from: draft.amountText), parsedAmount > 0 {
            amount = parsedAmount
        } else {
            return nil
        }
        guard
            !draft.store.trimmed.isEmpty,
            !draft.unit.trimmed.isEmpty,
            let price = LocalizedNumberParser.double(from: draft.priceText), price >= 0,
            let quantity = LocalizedNumberParser.positiveInteger(from: draft.purchaseQuantityText)
        else { return nil }
        return ValidatedPurchase(amount: amount, price: price, purchaseQuantity: quantity)
    }

    static func validateDraft(_ draft: PurchaseDraft) -> ValidatedPurchase? {
        let amount: Double
        if draft.amountText.trimmed.isEmpty {
            amount = 0
        } else if let parsedAmount = LocalizedNumberParser.double(from: draft.amountText), parsedAmount > 0 {
            amount = parsedAmount
        } else {
            return nil
        }
        guard
            let price = LocalizedNumberParser.double(from: draft.priceText), price >= 0,
            let quantity = LocalizedNumberParser.positiveInteger(from: draft.purchaseQuantityText)
        else { return nil }
        return ValidatedPurchase(amount: amount, price: price, purchaseQuantity: quantity)
    }
}

enum PurchaseSaveMode: Equatable {
    case disabled
    case draft
    case complete

    static func evaluate(
        draft: PurchaseDraft,
        requiresProductName: Bool,
        hasPhotoForDraft: Bool
    ) -> Self {
        if PurchaseValidator.validate(draft, requiresProductName: requiresProductName) != nil {
            return .complete
        }
        if hasPhotoForDraft, PurchaseValidator.validateDraft(draft) != nil {
            return .draft
        }
        return .disabled
    }

    var title: String { self == .draft ? "暫存" : "儲存" }
    var isEnabled: Bool { self != .disabled }
}

enum LocalizedNumberParser {
    private static let lock = NSLock()
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        return formatter
    }()

    static func double(from text: String) -> Double? {
        let value = text.trimmed
        guard !value.isEmpty else { return nil }
        lock.lock()
        let number = decimalFormatter.number(from: value)
        lock.unlock()
        return number?.doubleValue ?? Double(value.replacingOccurrences(of: ",", with: "."))
    }

    static func positiveInteger(from text: String) -> Int? {
        guard let value = Int(text.trimmed), value > 0 else { return nil }
        return value
    }
}

enum PriceCalculator {
    static func effectiveUnitPrice(totalPrice: Double, purchaseQuantity: Int, isBuyOneGetOne: Bool) -> Double {
        let purchasedUnits = Double(max(1, purchaseQuantity))
        return totalPrice / (isBuyOneGetOne ? purchasedUnits * 2 : purchasedUnits)
    }

    static func normalizedAmount(amount: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "g", "ml":
            let multiplier = ["kg", "公斤", "l", "公升"].contains(unit.trimmed.lowercased()) ? 1_000.0 : 1.0
            return amount * multiplier
        default:
            return nil
        }
    }

    static func normalizedUnit(_ unit: String) -> String? {
        switch unit.trimmed.lowercased() {
        case "g", "克", "kg", "公斤": return "g"
        case "ml", "毫升", "cc", "l", "公升": return "ml"
        default: return nil
        }
    }

    static func pricePerHundred(totalPrice: Double, purchaseQuantity: Int, isBuyOneGetOne: Bool, amount: Double, unit: String) -> Double? {
        guard let normalizedAmount = normalizedAmount(amount: amount, unit: unit), normalizedAmount > 0 else { return nil }
        return effectiveUnitPrice(totalPrice: totalPrice, purchaseQuantity: purchaseQuantity, isBuyOneGetOne: isBuyOneGetOne) / normalizedAmount * 100
    }
}

enum StoreIdentity {
    static func key(name: String, branch: String, city: String, district: String) -> String {
        [name, branch, city, district].map(normalize).joined(separator: "|")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmed
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
