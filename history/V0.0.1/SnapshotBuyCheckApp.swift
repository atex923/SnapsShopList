import SwiftData
import SwiftUI

@main
struct SnapshotBuyCheckApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            Product.self,
            PurchaseRecord.self,
            ProductPhoto.self
        ])

        do {
            let cloudConfiguration = ModelConfiguration(
                "SnapshotBuyCheck",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(
                for: schema,
                configurations: [cloudConfiguration]
            )
        } catch {
            // 即使 iCloud 暫時未登入，仍可使用本機資料庫。
            let localConfiguration = ModelConfiguration(
                "SnapshotBuyCheckLocal",
                schema: schema,
                cloudKitDatabase: .none
            )
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: [localConfiguration]
                )
            } catch {
                fatalError("無法建立資料庫：\(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }
}
