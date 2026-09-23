import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var quickModeSession: QuickModeSession
    @Query private var products: [Product]
    @Query private var records: [PurchaseRecord]
    @Query private var photos: [ProductPhoto]
    @Query private var stores: [StorePreset]
    @Query private var shoppingItems: [ShoppingListItem]
    @Query private var pantryEntries: [PantryEntry]

    @AppStorage("SnapshotBuyCheck.lastBackupTimestamp") private var lastBackupTimestamp = 0.0
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false
    @AppStorage(OverseasModeSettings.currencyKey) private var defaultCurrencyCode = SupportedCurrency.TWD.rawValue
    @AppStorage(SyncSettings.providerKey) private var syncProviderRaw = SyncProvider.disabled.rawValue
    @AppStorage(SyncSettings.automaticSyncKey) private var automaticSyncEnabled = false
    @AppStorage(SyncSettings.wifiOnlyKey) private var syncWiFiOnly = true
    @AppStorage(SyncSettings.includePhotosKey) private var syncIncludesPhotos = true
    @AppStorage(SyncSettings.lastSuccessKey) private var lastSyncTimestamp = 0.0
    @AppStorage(SyncSettings.lastStatusKey) private var lastSyncStatus = "尚未同步"
    @AppStorage(SyncSettings.locationBookmarkKey) private var syncLocationBookmark = Data()
    @AppStorage(SyncSettings.locationNameKey) private var syncLocationName = ""
    @AppStorage(QuickModeSettings.showToggleKey) private var showQuickModeToggle = false
    @State private var exportDocument: SnapsBackupDocument?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var pendingImport: SnapsBackupArchive?
    @State private var isImportConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isWorking = false
    @State private var statusMessage = ""
    @State private var isSyncLocationPickerPresented = false
    @State private var isCreateSyncConfirmationPresented = false
    @State private var pendingSyncEnvelope: SnapsSyncEnvelope?
    @State private var pendingSyncURL: URL?
    @State private var isSyncDirectionPresented = false
    @State private var syncBackups: [SyncBackupInfo] = []
    @State private var pendingRestore: SyncBackupInfo?
    @State private var isRestoreConfirmationPresented = false

    var body: some View {
        Form {
            overseasModeSection
            cloudSyncSection
            backupSection
            dataStatisticsSection
            removalPreparationSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .appModeBackground()
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSyncBackups() }
        .onChange(of: showQuickModeToggle) { _, isVisible in
            if !isVisible { quickModeSession.isEnabled = false }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .snapsShopListBackup,
            defaultFilename: backupFilename
        ) { result in
            if case .success = result {
                lastBackupTimestamp = Date.now.timeIntervalSince1970
                statusMessage = "完整備份已儲存至選擇的 iCloud Drive 或 Google Drive 位置。"
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
        .fileImporter(
            isPresented: $isSyncLocationPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            saveSyncLocation(result)
        }
        .confirmationDialog(
            "雲端位置內沒有同步檔",
            isPresented: $isCreateSyncConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("建立新同步檔並開始同步") { createNewSyncFileAndStart() }
            Button("取消", role: .cancel) { clearPendingSync() }
        } message: {
            Text("將在已設定的 \(syncProvider.displayName) 位置建立 SnapsShopList.snapssync，並把目前手機資料寫入第一個同步版本。")
        }
        .confirmationDialog(
            "選擇資料衝突處理方式",
            isPresented: $isSyncDirectionPresented,
            titleVisibility: .visible
        ) {
            Button("雲端修改優先") { performPendingSync(.synchronize) }
            Button("手機修改優先") { performPendingSync(.merge) }
            Button("取消", role: .cancel) { clearPendingSync() }
        } message: {
            Text("兩端新增的不同資料都會保留；相同資料若內容不同，請選擇優先版本。同步前的手機資料已備份，可從最近3次備份還原。")
        }
        .confirmationDialog(
            "還原這份同步前備份？",
            isPresented: $isRestoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("建立目前備份後還原", role: .destructive) { restorePendingBackup() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("將還原到 \(backup.createdAt.formatted(date: .numeric, time: .shortened))；目前資料會先另建一份備份。")
            }
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
                Text("\(archive.products.count) 項商品、\(archive.recordCount) 筆紀錄、\(archive.photoCount) 張照片、\(archive.pantryCount) 筆食材庫歷史；建立於 \(archive.createdAt.formatted(date: .numeric, time: .shortened))。")
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
            Text("商品、採買紀錄、照片、店家、待買清單及食材庫歷史都會刪除。建議先建立完整備份。")
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

    private var overseasModeSection: some View {
        Section {
            Toggle("顯示快速模式開關", isOn: $showQuickModeToggle)
            Toggle("海外模式", isOn: $overseasModeEnabled)

            if overseasModeEnabled {
                Picker("使用貨幣", selection: $defaultCurrencyCode) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text(currency.displayName).tag(currency.rawValue)
                    }
                }

                Label("外文文字擷取與名稱查詢已啟用", systemImage: "character.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader(
                title: "使用模式",
                message: "國內模式以快速記錄為主，使用台幣且不載入外文工具。海外模式會顯示貨幣、OCR及外文名稱查詢；切換模式不會改寫既有資料。"
            )
        } footer: {
            Text(showQuickModeToggle ? "首頁可在本次執行期間切換快速模式；完全關閉 App 後會自動關閉。" : (overseasModeEnabled ? "目前使用海外模式。" : "目前使用國內模式。"))
        }
    }

    private var dataMode: String {
        #if DEBUG
        "本機資料庫（測試版）"
        #else
        "iCloud CloudKit"
        #endif
    }

    private var syncProvider: SyncProvider {
        SyncProvider(rawValue: syncProviderRaw) ?? .disabled
    }

    private var cloudSyncSection: some View {
        Section {
            Picker("雲端位置", selection: $syncProviderRaw) {
                ForEach(SyncProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .onChange(of: syncProviderRaw) { _, _ in
                syncLocationBookmark = Data()
                syncLocationName = ""
                lastSyncStatus = "雲端位置尚未設定"
            }

            Button("設定雲端位置", systemImage: "folder.badge.gearshape") {
                guard syncProvider != .disabled else {
                    statusMessage = "請先選擇 iCloud 或 Google Drive，再設定雲端位置。"
                    return
                }
                isSyncLocationPickerPresented = true
            }

            LabeledContent("已設定位置", value: syncLocationName.isEmpty ? "尚未設定" : syncLocationName)

            Toggle("自動同步", isOn: $automaticSyncEnabled)
                .disabled(syncProvider == .disabled)
                .onChange(of: automaticSyncEnabled) { _, enabled in
                    guard enabled else { return }
                    automaticSyncEnabled = false
                    statusMessage = "為避免手機與尚未完成的桌機版互相覆蓋，V0.7.0 暫不開放自動同步；請使用「立即同步」。"
                }
            Toggle("僅使用 Wi-Fi", isOn: $syncWiFiOnly)
                .disabled(syncProvider == .disabled)
            Toggle("同步商品照片", isOn: $syncIncludesPhotos)
                .disabled(syncProvider == .disabled)

            Button("立即同步", systemImage: "arrow.triangle.2.circlepath") {
                beginSyncFromCloudLocation()
            }
            .disabled(isWorking)

            LabeledContent("同步狀態", value: lastSyncStatus)
            if lastSyncTimestamp > 0 {
                LabeledContent("最後成功同步", value: lastSyncText)
            }
            LabeledContent("目前資料模式", value: dataMode)

            if !syncBackups.isEmpty {
                DisclosureGroup("最近3次同步前備份") {
                    ForEach(syncBackups) { backup in
                        Button {
                            pendingRestore = backup
                            isRestoreConfirmationPresented = true
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(backup.createdAt.formatted(date: .numeric, time: .shortened))
                                Text("\(backup.productCount) 項商品・\(backup.recordCount) 筆紀錄・\(backup.photoCount) 張照片")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            InfoSectionHeader(
                title: "資料同步",
                message: "自動同步預設關閉。先選擇 iCloud 或 Google Drive 並設定資料夾。按下立即同步會先建立手機備份，再自動檢查同步檔；沒有檔案時會詢問是否建立。雲端同步檔內保留最近3個版本。"
            )
        } footer: {
            Text(syncProvider.guidance)
        }
    }

    private var backupSection: some View {
        Section {
            Button("建立完整備份到雲端硬碟", systemImage: "externaldrive.badge.plus") {
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

        } header: {
            InfoSectionHeader(
                title: "備份與匯入",
                message: "完整備份包含商品、採買紀錄、店家、待買清單、食材庫歷史與照片。建立後可在系統檔案畫面選擇 iCloud Drive 或 Google Drive；這份獨立備份不等同資料同步。"
            )
        }
    }

    private var dataStatisticsSection: some View {
        Section("資料統計") {
            LabeledContent("商品", value: String(products.count))
            LabeledContent("採買紀錄", value: String(records.count))
            LabeledContent("照片", value: String(photos.count))
            LabeledContent("記住的店家", value: String(stores.count))
            LabeledContent("待買項目", value: String(shoppingItems.count))
            LabeledContent("食材庫歷史", value: String(pantryEntries.count))
        }
    }

    private var removalPreparationSection: some View {
        Section {
            Button("清除全部資料", systemImage: "trash", role: .destructive) {
                isDeleteConfirmationPresented = true
            }
            .disabled(products.isEmpty && stores.isEmpty && shoppingItems.isEmpty && pantryEntries.isEmpty)
        } header: {
            InfoSectionHeader(
                title: "移除 App 前準備",
                message: "iOS無法在刪除App時由App另外詢問。若只想釋放程式空間，可在iPhone儲存空間選擇「卸載App」保留文件與資料；正式刪除前請先建立完整備份。"
            )
        } footer: {
            Text("清除全部資料前會再次確認。")
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

    private var lastSyncText: String {
        Date(timeIntervalSince1970: lastSyncTimestamp)
            .formatted(date: .numeric, time: .shortened)
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "SnapsShopList_Backup_\(formatter.string(from: .now))"
    }

    private func refreshSyncBackups() {
        syncBackups = SyncBackupStore.list()
    }

    private func createSyncPreflightBackup() throws {
        _ = try SyncBackupStore.create(in: modelContext)
        refreshSyncBackups()
    }

    private func beginSyncFromCloudLocation() {
        guard syncProvider != .disabled else {
            statusMessage = "尚未選擇雲端位置，請先在設定中選擇 iCloud 或 Google Drive。"
            return
        }
        guard !syncLocationBookmark.isEmpty else {
            statusMessage = "尚未設定雲端資料夾，請先按「設定雲端位置」。"
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let folderURL = try SyncLocationStore.resolve(syncLocationBookmark)
            let hasAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { folderURL.stopAccessingSecurityScopedResource() } }
            let existingSyncURL = try SyncCoordinator.existingSyncFile(in: folderURL)
            try createSyncPreflightBackup()
            if let syncURL = existingSyncURL {
                let envelope = try SyncCoordinator.readEnvelope(from: syncURL)
                pendingSyncEnvelope = envelope
                pendingSyncURL = syncURL
                lastSyncStatus = "同步檔已找到"
                isSyncDirectionPresented = true
            } else {
                pendingSyncURL = SyncCoordinator.newSyncFileURL(in: folderURL)
                lastSyncStatus = "雲端位置內沒有同步檔"
                isCreateSyncConfirmationPresented = true
            }
        } catch {
            AppErrorLogger.record(error, category: "資料同步", context: "檢查雲端位置")
            lastSyncStatus = "無法檢查雲端位置"
            statusMessage = "無法存取已設定的雲端位置，請重新設定：\(error.localizedDescription)"
        }
    }

    private func saveSyncLocation(_ result: Result<URL, Error>) {
        do {
            let folderURL = try result.get()
            let hasAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { folderURL.stopAccessingSecurityScopedResource() } }
            syncLocationBookmark = try SyncLocationStore.bookmark(for: folderURL)
            syncLocationName = folderURL.lastPathComponent
            lastSyncStatus = "雲端位置已設定"
            statusMessage = "已設定 \(syncProvider.displayName) 位置：\(folderURL.lastPathComponent)"
        } catch CocoaError.userCancelled {
            return
        } catch {
            AppErrorLogger.record(error, category: "資料同步", context: "設定雲端位置")
            syncLocationBookmark = Data()
            syncLocationName = ""
            lastSyncStatus = "雲端位置設定失敗"
            statusMessage = "無法保存雲端位置：\(error.localizedDescription)"
        }
    }

    private func createNewSyncFileAndStart() {
        guard let syncURL = pendingSyncURL else { return }
        isWorking = true
        defer {
            isWorking = false
            clearPendingSync()
        }
        do {
            let folderURL = try SyncLocationStore.resolve(syncLocationBookmark)
            let hasAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { folderURL.stopAccessingSecurityScopedResource() } }
            let archive = try BackupManager.makeArchive(
                in: modelContext,
                includePhotos: syncIncludesPhotos
            )
            let envelope = SnapsSyncEnvelope.initial(archive: archive, provider: syncProvider)
            try SyncCoordinator.write(envelope, to: syncURL)
            let verified = try SyncCoordinator.readEnvelope(from: syncURL)
            guard verified.updatedAt == envelope.updatedAt else { throw SyncError.unreadableFile }
            lastSyncTimestamp = Date.now.timeIntervalSince1970
            lastSyncStatus = "同步完成（已建立新檔）"
            statusMessage = "新同步檔已建立並完成第一次同步；手機與雲端資料都已有備援。"
        } catch {
            AppErrorLogger.record(error, category: "資料同步", context: "建立新同步檔")
            lastSyncStatus = "建立同步檔失敗"
            statusMessage = "無法建立同步檔：\(error.localizedDescription)"
        }
    }

    private func performPendingSync(_ mode: BackupImportMode) {
        guard let envelope = pendingSyncEnvelope, let url = pendingSyncURL else { return }
        isWorking = true
        defer {
            isWorking = false
            clearPendingSync()
        }

        do {
            let folderURL = try SyncLocationStore.resolve(syncLocationBookmark)
            let hasAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { folderURL.stopAccessingSecurityScopedResource() } }
            _ = try BackupManager.importArchive(envelope.current, mode: mode, in: modelContext)
            let mergedArchive = try BackupManager.makeArchive(
                in: modelContext,
                includePhotos: syncIncludesPhotos
            )
            let updatedEnvelope = envelope.updating(with: mergedArchive, provider: syncProvider)
            try SyncCoordinator.write(updatedEnvelope, to: url)
            let verified = try SyncCoordinator.readEnvelope(from: url)
            guard verified.updatedAt == updatedEnvelope.updatedAt else { throw SyncError.unreadableFile }
            lastSyncTimestamp = Date.now.timeIntervalSince1970
            lastSyncStatus = "同步完成"
            statusMessage = "資料同步完成；手機與同步檔都已保留最近3次備援。"
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料同步", context: syncProvider.displayName)
            lastSyncStatus = "同步失敗"
            statusMessage = "同步失敗，手機資料可由同步前備份還原：\(error.localizedDescription)"
        }
    }

    private func clearPendingSync() {
        pendingSyncEnvelope = nil
        pendingSyncURL = nil
    }

    private func restorePendingBackup() {
        guard let backup = pendingRestore else { return }
        isWorking = true
        defer {
            isWorking = false
            pendingRestore = nil
            refreshSyncBackups()
        }
        do {
            let summary = try SyncBackupStore.restore(backup, in: modelContext)
            lastSyncStatus = "已還原本機備份，尚未同步"
            statusMessage = "還原完成：\(summary.products) 項商品、\(summary.records) 筆紀錄、\(summary.photos) 張照片。"
        } catch {
            modelContext.rollback()
            AppErrorLogger.record(error, category: "資料還原", context: "同步前備份")
            statusMessage = "還原失敗：\(error.localizedDescription)"
        }
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
            statusMessage = "匯入完成：新增 \(summary.products) 項商品、\(summary.records) 筆紀錄、\(summary.photos) 張照片、\(summary.pantryEntries) 筆食材庫歷史。"
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
