import Foundation
import SwiftUI

/// Simple in-app debug logger that captures logs for display
/// Logs are also printed to console for Xcode debugging
@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var logs: [LogEntry] = []
    private let maxLogs = 100

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String {
            case info = "INFO"
            case warn = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
        }

        var formatted: String {
            let time = timestamp.formatted(date: .omitted, time: .standard)
            return "[\(time)] [\(level.rawValue)] [\(category)] \(message)"
        }
    }

    private init() {}

    func log(_ message: String, level: LogEntry.Level = .info, category: String = "VLM") {
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        logs.append(entry)

        // Trim old logs
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        // Also print to console for Xcode
        print(entry.formatted)
    }

    func info(_ message: String, category: String = "VLM") {
        log(message, level: .info, category: category)
    }

    func warn(_ message: String, category: String = "VLM") {
        log(message, level: .warn, category: category)
    }

    func error(_ message: String, category: String = "VLM") {
        log(message, level: .error, category: category)
    }

    func debug(_ message: String, category: String = "VLM") {
        log(message, level: .debug, category: category)
    }

    func clear() {
        logs.removeAll()
    }

    /// Get recent logs as a string for copying/sharing
    func exportLogs() -> String {
        logs.map { $0.formatted }.joined(separator: "\n")
    }
}

// MARK: - Log Viewer View

struct DebugLogViewer: View {
    @ObservedObject var logger = DebugLogger.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Debug Logs (\(logger.logs.count))")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    logger.clear()
                }
                .buttonStyle(.bordered)
                #if os(iOS)
                Button("Copy All") {
                    UIPasteboard.general.string = logger.exportLogs()
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Log list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logger.logs) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: logger.logs.count) { _ in
                    if autoScroll, let last = logger.logs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private func logRow(_ entry: DebugLogger.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 40)

            Text("[\(entry.category)]")
                .font(.caption2)
                .foregroundStyle(.purple)

            Text(entry.message)
                .font(.caption2)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func colorForLevel(_ level: DebugLogger.LogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .warn: return .orange
        case .error: return .orange
        case .debug: return .gray
        }
    }
}

// MARK: - Global convenience functions

/// Log info message - safe to call from any thread
nonisolated func vlmLog(_ message: String, category: String = "VLM") {
    let entry = "[\(category)] \(message)"
    print(entry)
    Task { @MainActor in
        DebugLogger.shared.info(message, category: category)
    }
}

/// Log warning message - safe to call from any thread
nonisolated func vlmWarn(_ message: String, category: String = "VLM") {
    let entry = "[WARN][\(category)] \(message)"
    print(entry)
    Task { @MainActor in
        DebugLogger.shared.warn(message, category: category)
    }
}

/// Log error message - safe to call from any thread
nonisolated func vlmError(_ message: String, category: String = "VLM") {
    let entry = "[ERROR][\(category)] \(message)"
    print(entry)
    Task { @MainActor in
        DebugLogger.shared.error(message, category: category)
    }
}
