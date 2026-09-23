import Foundation

@main
enum PurchaseLogicSmoke {
    static func main() {
        precondition(PriceCalculator.effectiveUnitPrice(totalPrice: 120, purchaseQuantity: 3, isBuyOneGetOne: false) == 40)
        precondition(PriceCalculator.effectiveUnitPrice(totalPrice: 120, purchaseQuantity: 3, isBuyOneGetOne: true) == 20)
        precondition(PriceCalculator.pricePerHundred(totalPrice: 60, purchaseQuantity: 1, isBuyOneGetOne: true, amount: 300, unit: "g") == 10)
        precondition(PriceCalculator.normalizedAmount(amount: 1.5, unit: "公斤") == 1_500)
        precondition(StoreIdentity.key(name: " 全 聯 ", branch: "信義店", city: "台北市", district: "信義區") == StoreIdentity.key(name: "全 聯", branch: "信義店", city: "台北市", district: "信義區"))

        let valid = PurchaseDraft(productName: "牛奶", store: "商店", amountText: "1000", unit: "ml", priceText: "89", purchaseQuantityText: "2")
        precondition(PurchaseValidator.validate(valid, requiresProductName: true) != nil)
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
        print("PurchaseLogic smoke tests passed")
    }
}
