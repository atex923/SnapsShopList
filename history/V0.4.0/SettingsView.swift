import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @Query private var records: [PurchaseRecord]
    @Query private var photos: [ProductPhoto]
    @Query private var stores: [StorePreset]
    @Query private var shoppingItems: [ShoppingListItem]

    @AppStorage("SnapshotBuyCheck.lastBackupTimestamp") private var lastBackupTimestamp = 0.0
    @State private var exportDocument: SnapsBackupDocument?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var pendingImport: SnapsBackupArchive?
    @State private var isImportConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isWorking = false
    @State private var statusMessage = ""

    var body: some View {
        Form {
            syncStatusSection
            backupSection
            dataStatisticsSection
            removalPreparationSection
            aboutSection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .snapsShopListBackup,
            defaultFilename: backupFilename
        ) { result in
            if case .success = result {
                lastBackupTimestamp = Date.now.timeIntervalSince1970
                statusMessage = "完整備份已儲存。"
            } else if case .failure(let error) = result {
                statusMessage = "備份失敗：\(error.localizedDescription)"
                AppErrorLogger.record(error, category: "資料備份")
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.snapsShopListBackup, .json]
        ) { result in
            readImport(result)
        }
        .confirmationDialog(
            "匯入這份備份？",
            isPresented: $isImportConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("合併並排除重複資料") { importPending(.merge) }
            Button("清除現有資料後還原", role: .destructive) { importPending(.replace) }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            if let archive = pendingImport {
                Text("\(archive.products.count) 項商品、\(archive.recordCount) 筆紀錄、\(archive.photoCount) 張照片；建立於 \(archive.createdAt.formatted(date: .numeric, time: .shortened))。")
            }
        }
        .confirmationDialog(
            "確定清除全部資料？",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("永久清除", role: .destructive) { deleteAllData() }
            Button("先建立備份") { prepareBackup() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("商品、採買紀錄、照片、店家及待買清單都會刪除。建議先建立完整備份。")
        }
        .alert("資料管理", isPresented: Binding(
            get: { !statusMessage.isEmpty },
            set: { if !$0 { statusMessage = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }
    }

    private var dataMode: String {
        #if DEBUG
        "本機資料庫（測試版）"
        #else
        "iCloud CloudKit"
        #endif
    }

    private var syncStatusSection: some View {
        Section("同步狀態") {
            LabeledContent("目前資料模式", value: dataMode)
            Text("iCloud 即時同步與備份檔是兩個獨立功能；刪除同步資料也可能影響其他裝置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var backupSection: some View {
        Section("備份與匯入") {
            Button("建立完整備份", systemImage: "externaldrive.badge.plus") {
                prepareBackup()
            }
            .disabled(isWorking)

            Button("匯入備份", systemImage: "square.and.arrow.down") {
                isImporterPresented = true
            }
            .disabled(isWorking)

            if lastBackupTimestamp > 0 {
                LabeledContent("上次成功備份", value: lastBackupText)
            }

            Text("系統檔案畫面可選擇 iCloud Drive、Google Drive、我的 iPhone或其他檔案服務。完整備份包含商品、採買紀錄、店家、待買清單及照片。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataStatisticsSection: some View {
        Section("資料統計") {
            LabeledContent("商品", value: String(products.count))
            LabeledContent("採買紀錄", value: String(records.count))
            LabeledContent("照片", value: String(photos.count))
            LabeledContent("記住的店家", value: String(stores.count))
            LabeledContent("待買項目", value: String(shoppingItems.count))
        }
    }

    private var removalPreparationSection: some View {
        Section {
            Text("iOS 無法讓 App 在使用者刪除程式時另外詢問。移除前請先建立完整備份；若只想釋放程式空間，可在 iPhone 儲存空間使用「卸載 App」保留本機文件與資料。")
                .font(.caption)

            Button("清除全部資料", systemImage: "trash", role: .destructive) {
                isDeleteConfirmationPresented = true
            }
            .disabled(products.isEmpty && stores.isEmpty && shoppingItems.isEmpty)
        } header: {
            Text("移除 App 前準備")
        } footer: {
            Text("清除全部資料無法復原。正式啟用 CloudKit 後，刪除也可能同步到其他裝置；iCloud Drive或Google Drive中的手動備份檔不會自動刪除。")
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            LabeledContent("程式", value: "購物記本")
            LabeledContent("版本", value: AppTheme.version)
            LabeledContent("製作日期", value: AppTheme.buildDate)
            LabeledContent("程式設計者", value: "Atex Lin")
            NavigationLink("程式錯誤紀錄") { ErrorLogView() }
        }
    }

    private var lastBackupText: String {
        Date(timeIntervalSince1970: lastBackupTimestamp)
            .formatted(date: .numeric, time: .shortened)
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "SnapsShopList_Backup_\(formatter.string(from: .now))"
    }

    private func prepareBackup() {
        isWorking = true
        defer { isWorking = false }
        do {
            exportDocument = SnapsBackupDocument(archive: try BackupManager.makeArchive(in: modelContext))
            isExporterPresented = true
        } catch {
            AppErrorLogger.record(error, category: "資料備份")
            statusMessage = "無法建立備份：\(error.localizedDescription)"
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let archive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: data)
            try BackupManager.validate(archive)
            pendingImport = archive
            isImportConfirmationPresented = true
        } catch {
            AppErrorLogger.record(error, category: "資料匯入")
            statusMessage = "無法讀取備份：\(error.localizedDescription)"
        }
    }

    private func importPending(_ mode: BackupImportMode) {
        guard let archive = pendingImport else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let summary = try BackupManager.importArchive(archive, mode: mode, in: modelContext)
            statusMessage = "匯入完成：新增 \(summary.products) 項商品、\(summary.records) 筆紀錄、\(summary.photos) 張照片。"
            pendingImport = nil
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料匯入")
            statusMessage = "匯入失敗，未完成的變更已取消：\(error.localizedDescription)"
        }
    }

    private func deleteAllData() {
        do {
            try BackupManager.deleteAll(in: modelContext)
            statusMessage = "全部商品資料已清除；手動備份檔仍保留在原位置。"
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料清除")
            statusMessage = "清除失敗：\(error.localizedDescription)"
        }
    }
}
