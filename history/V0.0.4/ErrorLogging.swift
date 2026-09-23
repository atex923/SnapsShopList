import Foundation
import OSLog
import SwiftUI

struct AppErrorEntry: Codable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let category: String
    let message: String
    let context: String
}

enum AppErrorLogger {
    private static let logger = Logger(
        subsystem: "com.atex1.SnapshotBuyCheck",
        category: "Runtime"
    )
    private static let lock = NSLock()
    private static let maximumEntryCount = 200

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("SnapshotBuyCheck", isDirectory: true)
            .appendingPathComponent("error-log.json")
    }

    static func record(_ error: Error, category: String, context: String = "") {
        record(message: error.localizedDescription, category: category, context: context)
    }

    static func record(message: String, category: String, context: String = "") {
        logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        lock.lock()
        defer { lock.unlock() }

        var entries = loadUnlocked()
        entries.insert(AppErrorEntry(
            id: UUID(),
            occurredAt: .now,
            category: category,
            message: message,
            context: context
        ), at: 0)
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.snapshotBuyCheck.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("無法寫入錯誤紀錄：\(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> [AppErrorEntry] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    static func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func loadUnlocked() -> [AppErrorEntry] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let entries = try? JSONDecoder.snapshotBuyCheck.decode([AppErrorEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.occurredAt > $1.occurredAt }
    }
}

private extension JSONEncoder {
    static var snapshotBuyCheck: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var snapshotBuyCheck: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct ErrorLogView: View {
    @State private var entries: [AppErrorEntry] = []
    @State private var isClearConfirmationPresented = false
    @State private var clearError = ""

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "沒有程式錯誤紀錄",
                    systemImage: "checkmark.shield",
                    description: Text("發生執行錯誤時會在此保留最近 200 筆。")
                )
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.category)
                                .font(.headline)
                            Spacer()
                            Text(entry.occurredAt.formatted(date: .numeric, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.subheadline)
                            .textSelection(.enabled)
                        if !entry.context.isEmpty {
                            Text(entry.context)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("程式錯誤紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除", systemImage: "trash", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .onAppear { entries = AppErrorLogger.load() }
        .confirmationDialog(
            "清除全部錯誤紀錄？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) { clearEntries() }
            Button("取消", role: .cancel) {}
        }
        .alert("無法清除", isPresented: Binding(
            get: { !clearError.isEmpty },
            set: { if !$0 { clearError = "" } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(clearError)
        }
    }

    private func clearEntries() {
        do {
            try AppErrorLogger.clear()
            entries = []
        } catch {
            clearError = error.localizedDescription
        }
    }
}
