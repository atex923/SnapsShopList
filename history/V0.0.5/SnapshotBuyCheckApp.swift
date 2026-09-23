import SwiftData
import SwiftUI

@main
struct SnapshotBuyCheckApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            Product.self,
            PurchaseRecord.self,
            ProductPhoto.self,
            StorePreset.self,
            ShoppingListItem.self
        ])

        #if DEBUG
        do {
            let localConfiguration = ModelConfiguration(
                "SnapshotBuyCheckLocal",
                schema: schema,
                cloudKitDatabase: .none
            )
            container = try ModelContainer(
                for: schema,
                configurations: [localConfiguration]
            )
        } catch {
            AppErrorLogger.record(error, category: "資料庫", context: "建立本機資料庫")
            fatalError("無法建立本機資料庫：\(error.localizedDescription)")
        }
        #else
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
            AppErrorLogger.record(error, category: "iCloud", context: "CloudKit 無法啟動，改用本機資料庫")
            // iCloud 暫時不可用時，沿用舊版的本機資料庫名稱。
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
                AppErrorLogger.record(error, category: "資料庫", context: "CloudKit 與本機資料庫皆無法建立")
                fatalError("無法建立資料庫：\(error.localizedDescription)")
            }
        }
        #endif

        let migrationContainer = container
        Task { @MainActor in
            Self.migrateLegacyPhotoData(in: migrationContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }

    @MainActor
    private static func migrateLegacyPhotoData(in container: ModelContainer) {
        let context = ModelContext(container)
        let photos: [ProductPhoto]
        do {
            photos = try context.fetch(FetchDescriptor<ProductPhoto>())
        } catch {
            AppErrorLogger.record(error, category: "資料遷移", context: "讀取舊版商品照片索引")
            return
        }
        var hasChanges = false

        for photo in photos where photo.imageData == nil && !photo.fileName.isEmpty {
            let url = ProductPhotoStore.folderURL.appendingPathComponent(photo.fileName)
            do {
                photo.imageData = try Data(contentsOf: url)
                hasChanges = true
            } catch {
                AppErrorLogger.record(
                    error,
                    category: "資料遷移",
                    context: "讀取舊版照片：\(photo.fileName)"
                )
            }
        }

        if hasChanges {
            do {
                try context.save()
            } catch {
                AppErrorLogger.record(error, category: "資料遷移", context: "補入舊版商品照片")
            }
        }
    }
}
