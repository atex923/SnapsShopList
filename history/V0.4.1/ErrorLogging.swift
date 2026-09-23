import Foundation
import OSLog
import SwiftUI
import UIKit

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

    private static var folderURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("SnapshotBuyCheck", isDirectory: true)
    }

    private static var entriesURL: URL {
        folderURL.appendingPathComponent("error-log.json")
    }

    static var fileURL: URL {
        folderURL.appendingPathComponent("SnapsShopList-runtime.log")
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
                at: folderURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.snapshotBuyCheck.encode(entries)
            try data.write(to: entriesURL, options: .atomic)
        } catch {
            logger.error("無法寫入錯誤紀錄：\(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> [AppErrorEntry] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    static func prepareShareFile() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        try writeLogFile(loadUnlocked())
        return fileURL
    }

    static func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        for url in [entriesURL, fileURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func loadUnlocked() -> [AppErrorEntry] {
        guard
            let data = try? Data(contentsOf: entriesURL),
            let entries = try? JSONDecoder.snapshotBuyCheck.decode([AppErrorEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.occurredAt > $1.occurredAt }
    }

    private static func writeLogFile(_ entries: [AppErrorEntry]) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let lines = entries.map { entry in
            let context = entry.context.isEmpty ? "" : " | context=\(singleLine(entry.context))"
            return "[\(formatter.string(from: entry.occurredAt))] [\(singleLine(entry.category))] \(singleLine(entry.message))\(context)"
        }
        let header = "SnapsShopList \(AppTheme.version) runtime error log\n"
        let text = header + lines.joined(separator: "\n") + "\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
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
    @State private var shareFile: LogShareFile?

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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    prepareShareFile()
                } label: {
                    Label("分享 Log", systemImage: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)

                Button("清除", systemImage: "trash", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .onAppear { entries = AppErrorLogger.load() }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
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

    private func prepareShareFile() {
        do {
            shareFile = LogShareFile(url: try AppErrorLogger.prepareShareFile())
        } catch {
            clearError = error.localizedDescription
        }
    }
}

private struct LogShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
