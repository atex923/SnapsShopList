import SwiftData
import SwiftUI

@main
struct SnapsShopListApp: App {
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
            try? await Task.sleep(for: .seconds(1.2))
            let migrationKey = "SnapshotBuyCheck.didConsolidateDataV007"
            guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
            let consolidator = LegacyDataConsolidator(modelContainer: migrationContainer)
            if await consolidator.consolidate() {
                UserDefaults.standard.set(true, forKey: migrationKey)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            debugRootView
        }
        .modelContainer(container)
    }

    @ViewBuilder
    private var debugRootView: some View {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SNAPS_DEBUG_SCREEN"] {
        case "settings":
            NavigationStack { SettingsView() }
        case "scanner":
            BarcodeScannerSheet(onCode: { _ in }, onNoBarcode: {})
        case "history":
            NavigationStack { ProductHistoryView() }
        default:
            HomeView()
        }
        #else
        HomeView()
        #endif
    }
}

@ModelActor
private actor LegacyDataConsolidator {
    func consolidate() -> Bool {
        let photos: [ProductPhoto]
        do {
            photos = try modelContext.fetch(FetchDescriptor<ProductPhoto>())
        } catch {
            AppErrorLogger.record(error, category: "資料遷移", context: "讀取舊版商品照片索引")
            return false
        }
        var hasChanges = false
        var completedWithoutError = true

        for photo in photos where photo.imageData == nil && !photo.fileName.isEmpty {
            let url = ProductPhotoStore.folderURL.appendingPathComponent(photo.fileName)
            do {
                photo.imageData = try Data(contentsOf: url)
                hasChanges = true
            } catch {
                completedWithoutError = false
                AppErrorLogger.record(
                    error,
                    category: "資料遷移",
                    context: "讀取舊版照片：\(photo.fileName)"
                )
            }
        }

        if hasChanges {
            do {
                try modelContext.save()
            } catch {
                AppErrorLogger.record(error, category: "資料遷移", context: "補入舊版商品照片")
                return false
            }
        }

        // Only remove legacy files after every indexed photo has SwiftData data.
        if completedWithoutError && photos.allSatisfy({ $0.imageData != nil || $0.fileName.isEmpty }) {
            for photo in photos where !photo.fileName.isEmpty {
                ProductPhotoStore.delete(fileName: photo.fileName)
                photo.fileName = ""
                hasChanges = true
            }
        }

        do {
            let presets = try modelContext.fetch(FetchDescriptor<StorePreset>())
            for preset in presets {
                let key = StoreIdentity.key(
                    name: preset.name,
                    branch: preset.branch,
                    city: preset.city,
                    district: preset.district
                )
                if preset.normalizedKey != key {
                    preset.normalizedKey = key
                    hasChanges = true
                }
            }
            if hasChanges { try modelContext.save() }
        } catch {
            AppErrorLogger.record(error, category: "資料遷移", context: "整理照片與店家索引")
            return false
        }
        return completedWithoutError
    }
}
