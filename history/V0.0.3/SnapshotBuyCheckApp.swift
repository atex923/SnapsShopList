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
        guard let photos = try? context.fetch(FetchDescriptor<ProductPhoto>()) else { return }
        var hasChanges = false

        for photo in photos where photo.imageData == nil && !photo.fileName.isEmpty {
            let url = ProductPhotoStore.folderURL.appendingPathComponent(photo.fileName)
            guard let data = try? Data(contentsOf: url) else { continue }
            photo.imageData = data
            hasChanges = true
        }

        if hasChanges {
            try? context.save()
        }
    }
}
