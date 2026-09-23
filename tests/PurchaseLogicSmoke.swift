import Foundation

@main
enum PurchaseLogicSmoke {
    static func main() {
        precondition(PriceCalculator.effectiveUnitPrice(totalPrice: 120, purchaseQuantity: 3, isBuyOneGetOne: false) == 40)
        precondition(PriceCalculator.effectiveUnitPrice(totalPrice: 120, purchaseQuantity: 3, isBuyOneGetOne: true) == 20)
        precondition(PriceCalculator.effectiveUnitPrice(
            totalPrice: 120,
            purchaseQuantity: 2,
            isBuyOneGetOne: false,
            groupContentCount: 3
        ) == 20)
        precondition(PriceCalculator.pricePerHundred(totalPrice: 60, purchaseQuantity: 1, isBuyOneGetOne: true, amount: 300, unit: "g") == 10)
        precondition(PriceCalculator.normalizedAmount(amount: 1.5, unit: "公斤") == 1_500)
        precondition(StoreIdentity.key(name: " 全 聯 ", branch: "信義店", city: "台北市", district: "信義區") == StoreIdentity.key(name: "全 聯", branch: "信義店", city: "台北市", district: "信義區"))

        let valid = PurchaseDraft(productName: "牛奶", store: "商店", amountText: "1000", unit: "ml", priceText: "89", purchaseQuantityText: "2")
        precondition(PurchaseValidator.validate(valid, requiresProductName: true) != nil)
        let grouped = PurchaseDraft(
            productName: "優格",
            store: "商店",
            amountText: "100",
            unit: "g",
            priceText: "120",
            purchaseQuantityText: "2",
            isGroupPackage: true,
            groupContentCountText: "3"
        )
        precondition(PurchaseValidator.validate(grouped, requiresProductName: true)?.groupContentCount == 3)
        var invalidGrouped = grouped
        invalidGrouped.groupContentCountText = "0"
        precondition(PurchaseValidator.validate(invalidGrouped, requiresProductName: true) == nil)
        let withoutOptionalFields = PurchaseDraft(productName: "牛奶", store: "商店", amountText: "", unit: "瓶", priceText: "89", purchaseQuantityText: "1")
        precondition(PurchaseValidator.validate(withoutOptionalFields, requiresProductName: true)?.amount == 0)
        let invalid = PurchaseDraft(productName: "", store: "商店", amountText: "0", unit: "g", priceText: "-1", purchaseQuantityText: "0")
        precondition(PurchaseValidator.validate(invalid, requiresProductName: true) == nil)
        let quickDraft = PurchaseDraft(productName: "", store: "", amountText: "", unit: "", priceText: "59", purchaseQuantityText: "1")
        precondition(PurchaseValidator.validateDraft(quickDraft)?.price == 59)
        precondition(PurchaseSaveMode.evaluate(draft: quickDraft, requiresProductName: true, hasPhotoForDraft: false) == .disabled)
        precondition(PurchaseSaveMode.evaluate(draft: quickDraft, requiresProductName: true, hasPhotoForDraft: true) == .draft)
        precondition(PurchaseSaveMode.evaluate(draft: valid, requiresProductName: true, hasPhotoForDraft: false) == .complete)
        precondition(PurchaseValidator.validateDraft(PurchaseDraft(priceText: "", purchaseQuantityText: "1")) == nil)
        precondition(SupportedCurrency.normalized("jpy") == .JPY)
        precondition(SupportedCurrency.normalized("unknown") == .TWD)
        precondition(SupportedCurrency.JPY.format(1_280) == "¥1,280")
        precondition(SupportedCurrency.USD.format(5.5) == "US$5.5")
        let oneLiter = PriceCalculator.referenceUnitPrice(
            totalPrice: 120,
            purchaseQuantity: 1,
            isBuyOneGetOne: false,
            amount: 1_500,
            unit: "ml"
        )
        precondition(oneLiter?.label == "每 1 L")
        precondition(abs((oneLiter?.value ?? 0) - 80) < 0.001)
        precondition(PriceCalculator.referenceUnitPrice(
            totalPrice: 100,
            purchaseQuantity: 1,
            isBuyOneGetOne: false,
            amount: 1_000,
            unit: "ml"
        )?.label == "每 100 ml")
        precondition(PurchaseCurrencyPolicy.activeCode(overseasModeEnabled: false, preferredCode: "JPY") == "TWD")
        precondition(PurchaseCurrencyPolicy.activeCode(overseasModeEnabled: true, preferredCode: "JPY") == "JPY")
        precondition(PurchaseCurrencyPolicy.activeCode(overseasModeEnabled: true, preferredCode: "unknown") == "TWD")
        precondition(testRecord(price: 100, currencyCode: "TWD").isForeignCurrencyPurchase == false)
        precondition(testRecord(price: 680, currencyCode: "JPY").isForeignCurrencyPurchase == true)
        precondition(testRecord(price: 8.99, currencyCode: "USD").isForeignCurrencyPurchase == true)
        let unknownQuantity = PurchaseRecord(
            store: "海外比價",
            price: 500,
            currencyCode: "JPY",
            amount: 100,
            unit: "g",
            isOnSale: false,
            isBuyOneGetOne: false,
            recordStatus: .comparison,
            quantityWasEntered: false
        )
        precondition(unknownQuantity.formattedEffectiveUnitPrice == "數量未填")
        precondition(unknownQuantity.referenceUnitPrice != nil)
        let previouslyUsedIngredient = Product(barcode: "manual:test-pantry", name: "已用畢食材")
        previouslyUsedIngredient.pantryEntries = [PantryEntry(
            purchasedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_700_086_400),
            usedUpAt: Date(timeIntervalSince1970: 1_700_043_200),
            product: previouslyUsedIngredient
        )]
        let neverAddedIngredient = Product(barcode: "manual:test-new", name: "未加入食材")
        let currentIngredient = Product(barcode: "manual:test-current", name: "目前在庫")
        currentIngredient.pantryEntries = [PantryEntry(
            purchasedAt: Date(timeIntervalSince1970: 1_600_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_600_086_400),
            product: currentIngredient
        )]
        precondition(PantryProductOrdering.precedes(currentIngredient, previouslyUsedIngredient))
        precondition(PantryProductOrdering.precedes(previouslyUsedIngredient, neverAddedIngredient))
        precondition(PantryHomeStatus.status(for: currentIngredient) == .inStock)
        precondition(PantryHomeStatus.status(for: previouslyUsedIngredient) == .usedUp)
        precondition(PantryHomeStatus.status(for: neverAddedIngredient) == nil)
        print("PurchaseLogic smoke tests passed")
    }

    private static func testRecord(price: Double, currencyCode: String) -> PurchaseRecord {
        PurchaseRecord(
            store: "測試店家",
            price: price,
            currencyCode: currencyCode,
            amount: 1,
            unit: "件",
            isOnSale: false,
            isBuyOneGetOne: false
        )
    }
}
