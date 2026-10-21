import Foundation
import UIKit

/// On-device evidence for background behavior (Low Power Mode, locked screen): one line
/// per Spotify poll and per keep-alive or lifecycle event, with the conditions at that
/// moment, in Documents/diagnostics.log. Pull it with scripts/pull-diagnostics.sh.
///
/// Append-only: rewriting the whole log on every poll wrote gigabytes a day, which a
/// background process should not do. Past 512 KB the log moves to diagnostics.old.log,
/// so the two files together keep the last few hours.
@MainActor
enum Diagnostics {
    private static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private static let url = directory.appendingPathComponent("diagnostics.log")
    private static let oldURL = directory.appendingPathComponent("diagnostics.old.log")
    private static let maxBytes: UInt64 = 512 * 1024
    private static var handle: FileHandle?
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func record(_ event: String, keepAlive: Bool) {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        default: state = "background"
        }
        let line = [
            formatter.string(from: Date()),
            event,
            "lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
            "app=\(state)",
            "protectedData=\(UIApplication.shared.isProtectedDataAvailable ? "unlocked" : "locked")",
            "keepAlive=\(keepAlive)",
        ].joined(separator: " ") + "\n"
        append(Data(line.utf8))
    }

    private static func append(_ data: Data) {
        do {
            let handle = try openHandle()
            try handle.write(contentsOf: data)
            if try handle.offset() > maxBytes { rotate() }
        } catch {
            // A log must never take the app down; drop the handle and retry next line.
            try? handle?.close()
            handle = nil
        }
    }

    private static func openHandle() throws -> FileHandle {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return opened
    }

    private static func rotate() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: url, to: oldURL)
    }
}
