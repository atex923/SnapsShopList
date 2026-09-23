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
        print("PurchaseLogic smoke tests passed")
    }
}
