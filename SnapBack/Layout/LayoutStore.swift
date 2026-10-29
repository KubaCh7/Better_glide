import CoreGraphics
import Foundation

/// One remembered window frame.
struct SavedWindow: Codable, Equatable {
    var bundleID: String
    var title: String
    /// Position among the app's windows (by creation order); fallback when titles change.
    var indexInApp: Int
    /// Global top-left coordinates.
    var frame: CGRect
}

struct SavedLayout: Codable, Equatable {
    var summary: String
    var savedAt: Date
    var windows: [SavedWindow]
}

/// Persists layouts per display configuration in
/// `~/Library/Application Support/SnapBack/layouts.json`.
final class LayoutStore {
    private(set) var layouts: [String: SavedLayout] = [:]
    private let fileURL: URL

    init(fileURL: URL = LayoutStore.defaultURL) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // must match `persist()`
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([String: SavedLayout].self, from: data) {
            layouts = decoded
        }
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SnapBack", isDirectory: true)
            .appendingPathComponent("layouts.json")
    }

    func layout(for key: String) -> SavedLayout? { layouts[key] }

    /// Merges a snapshot into the stored layout: apps present in the snapshot replace
    /// their previous entries, apps that are not running keep theirs (closing an app
    /// must not forget where its windows belong).
    func merge(_ windows: [SavedWindow], summary: String, for key: String, now: Date = Date()) {
        let snapshotApps = Set(windows.map(\.bundleID))
        let kept = layouts[key]?.windows.filter { !snapshotApps.contains($0.bundleID) } ?? []
        let merged = SavedLayout(summary: summary, savedAt: now, windows: kept + windows)
        guard merged.windows != layouts[key]?.windows else { return }
        layouts[key] = merged
        persist()
    }

    func removeAll() {
        layouts.removeAll()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(layouts).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SnapBack: failed to save layouts: \(error)")
        }
    }
}

/// Matches live windows to saved entries. Pure logic, unit-tested.
enum LayoutMatcher {
    struct LiveWindow: Equatable {
        let id: CGWindowID
        let bundleID: String
        let title: String
        let indexInApp: Int
    }

    /// Returns the saved frame for each live window that has a match. Passes, per app:
    /// 1. same title (most specific), 2. same index among the app's windows,
    /// 3. remaining saved entries in order. Each saved entry is used at most once.
    static func match(live: [LiveWindow], saved: [SavedWindow]) -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        let liveByApp = Dictionary(grouping: live, by: \.bundleID)
        let savedByApp = Dictionary(grouping: saved, by: \.bundleID)

        for (bundleID, windows) in liveByApp {
            var available = savedByApp[bundleID] ?? []
            var unmatched: [LiveWindow] = []

            for window in windows.sorted(by: { $0.indexInApp < $1.indexInApp }) {
                if !window.title.isEmpty, let i = available.firstIndex(where: { $0.title == window.title }) {
                    result[window.id] = available.remove(at: i).frame
                } else {
                    unmatched.append(window)
                }
            }
            var stillUnmatched: [LiveWindow] = []
            for window in unmatched {
                if let i = available.firstIndex(where: { $0.indexInApp == window.indexInApp }) {
                    result[window.id] = available.remove(at: i).frame
                } else {
                    stillUnmatched.append(window)
                }
            }
            for window in stillUnmatched where !available.isEmpty {
                result[window.id] = available.removeFirst().frame
            }
        }
        return result
    }
}
