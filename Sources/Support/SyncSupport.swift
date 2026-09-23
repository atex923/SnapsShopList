import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

extension UTType {
    static let snapsShopListSync = UTType(filenameExtension: "snapssync", conformingTo: .json) ?? .json
}

enum SyncProvider: String, CaseIterable, Identifiable {
    case disabled
    case iCloudDrive
    case googleDrive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: "不啟用"
        case .iCloudDrive: "iCloud"
        case .googleDrive: "Google Drive"
        }
    }

    var guidance: String {
        switch self {
        case .disabled:
            "資料只保留在本機；仍可使用手動完整備份。"
        case .iCloudDrive:
            "同步檔請存放在 iCloud Drive。手機與未來 macOS 版會使用同一份交換檔。"
        case .googleDrive:
            "同步檔請存放在 Google Drive。未來 macOS 與 Windows 版都能使用同一份交換檔。"
        }
    }
}

enum SyncSettings {
    static let schemaVersion = 5
    static let providerKey = "SnapsShopList.syncProvider"
    static let automaticSyncKey = "SnapsShopList.automaticSyncEnabled"
    static let wifiOnlyKey = "SnapsShopList.syncWiFiOnly"
    static let includePhotosKey = "SnapsShopList.syncIncludePhotos"
    static let lastSuccessKey = "SnapsShopList.lastSyncSuccess"
    static let lastStatusKey = "SnapsShopList.lastSyncStatus"
    static let locationBookmarkKey = "SnapsShopList.syncLocationBookmark"
    static let locationNameKey = "SnapsShopList.syncLocationName"
    static let backupRetentionCount = 3
    static let defaultFilename = "SnapsShopList.snapssync"
}

struct SnapsSyncEnvelope: Codable {
    let schemaVersion: Int
    let provider: String
    let updatedAt: Date
    let updatedBy: String
    let current: SnapsBackupArchive
    let history: [SnapsBackupArchive]

    static func initial(archive: SnapsBackupArchive, provider: SyncProvider) -> Self {
        .init(
            schemaVersion: SyncSettings.schemaVersion,
            provider: provider.rawValue,
            updatedAt: .now,
            updatedBy: deviceName,
            current: archive,
            history: []
        )
    }

    func updating(with archive: SnapsBackupArchive, provider: SyncProvider) -> Self {
        .init(
            schemaVersion: SyncSettings.schemaVersion,
            provider: provider.rawValue,
            updatedAt: .now,
            updatedBy: Self.deviceName,
            current: archive,
            history: Array(([current] + history).prefix(SyncSettings.backupRetentionCount))
        )
    }

    static var deviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Apple Device"
        #endif
    }
}

struct SnapsSyncDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.snapsShopListSync] }
    var envelope: SnapsSyncEnvelope

    init(envelope: SnapsSyncEnvelope) {
        self.envelope = envelope
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw SyncError.unreadableFile
        }
        envelope = try SyncCoding.decoder.decode(SnapsSyncEnvelope.self, from: data)
        try SyncCoordinator.validate(envelope)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try SyncCoding.encoder.encode(envelope))
    }
}

struct SyncBackupInfo: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let productCount: Int
    let recordCount: Int
    let photoCount: Int

    var id: URL { url }
}

enum SyncError: LocalizedError {
    case unreadableFile
    case unsupportedSchema(Int)
    case backupUnavailable
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "無法讀取同步檔。"
        case .unsupportedSchema(let version): "不支援同步格式版本 \(version)。"
        case .backupUnavailable: "同步前備份未完成，本次同步已取消。"
        case .locationUnavailable: "雲端位置無法存取，請重新設定雲端位置。"
        }
    }
}

enum SyncLocationStore {
    static func bookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ bookmark: Data) throws -> URL {
        guard !bookmark.isEmpty else { throw SyncError.locationUnavailable }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw SyncError.locationUnavailable }
        return url
    }
}

enum SyncCoding {
    static var encoder: JSONEncoder { BackupCoding.encoder }
    static var decoder: JSONDecoder { BackupCoding.decoder }
}

@MainActor
enum SyncBackupStore {
    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SnapsShopList/SyncBackups", isDirectory: true)
    }

    @discardableResult
    static func create(in context: ModelContext) throws -> SyncBackupInfo {
        let archive = try BackupManager.makeArchive(in: context)
        try BackupManager.validate(archive)
        let data = try BackupCoding.encoder.encode(archive)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let url = folderURL.appendingPathComponent("BeforeSync_\(formatter.string(from: .now)).snapsbackup")
        try data.write(to: url, options: [.atomic, .completeFileProtection])

        let decoded = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: Data(contentsOf: url))
        try BackupManager.validate(decoded)
        try rotateIfNeeded()
        return info(url: url, archive: decoded)
    }

    static func list() -> [SyncBackupInfo] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard
                let data = try? Data(contentsOf: url),
                let archive = try? BackupCoding.decoder.decode(SnapsBackupArchive.self, from: data),
                (try? BackupManager.validate(archive)) != nil
            else { return nil }
            return info(url: url, archive: archive)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func restore(_ info: SyncBackupInfo, in context: ModelContext) throws -> BackupImportSummary {
        let data = try Data(contentsOf: info.url)
        let archive = try BackupCoding.decoder.decode(SnapsBackupArchive.self, from: data)
        try BackupManager.validate(archive)
        _ = try create(in: context)
        return try BackupManager.importArchive(archive, mode: .replace, in: context)
    }

    private static func info(url: URL, archive: SnapsBackupArchive) -> SyncBackupInfo {
        .init(
            url: url,
            createdAt: archive.createdAt,
            productCount: archive.products.count,
            recordCount: archive.recordCount,
            photoCount: archive.photoCount
        )
    }

    private static func rotateIfNeeded() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in urls.dropFirst(SyncSettings.backupRetentionCount) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum SyncCoordinator {
    static func validate(_ envelope: SnapsSyncEnvelope) throws {
        guard (1...SyncSettings.schemaVersion).contains(envelope.schemaVersion) else {
            throw SyncError.unsupportedSchema(envelope.schemaVersion)
        }
        try BackupManager.validate(envelope.current)
        for archive in envelope.history.prefix(SyncSettings.backupRetentionCount) {
            try BackupManager.validate(archive)
        }
    }

    static func readEnvelope(from url: URL) throws -> SnapsSyncEnvelope {
        let data = try Data(contentsOf: url)
        let envelope = try SyncCoding.decoder.decode(SnapsSyncEnvelope.self, from: data)
        try validate(envelope)
        return envelope
    }

    static func write(_ envelope: SnapsSyncEnvelope, to url: URL) throws {
        try validate(envelope)
        let data = try SyncCoding.encoder.encode(envelope)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                #if os(iOS)
                try data.write(to: coordinatedURL, options: [.atomic, .completeFileProtection])
                #else
                try data.write(to: coordinatedURL, options: [.atomic])
                #endif
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func existingSyncFile(in folderURL: URL) throws -> URL? {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "snapssync" }

        if let preferred = urls.first(where: { $0.lastPathComponent == SyncSettings.defaultFilename }) {
            return preferred
        }
        return urls.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }.first
    }

    static func newSyncFileURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(SyncSettings.defaultFilename, isDirectory: false)
    }
}
