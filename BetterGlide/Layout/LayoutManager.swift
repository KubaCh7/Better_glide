import AppKit
import os

/// Snapshots window frames per display configuration and restores them when that
/// configuration comes back.
///
/// Snapshots are event-driven (app switches, our own switches, sleep, quit, right before
/// a display change) plus a low-frequency safety timer; each one costs a few ms.
/// During a display change snapshots are suspended, so the positions macOS uses while
/// shuffling windows between screens never overwrite the remembered layout.
final class LayoutManager {
    private let tracker: WindowTracker
    private let store: LayoutStore
    private let settings: AppSettings
    private let observer = DisplayConfigObserver()
    private var snapshotsSuspended = false
    private var lastSnapshot = Date.distantPast
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var restoreWork: [DispatchWorkItem] = []
    private let log = Logger(subsystem: "com.betterglide.BetterGlide", category: "layout")

    /// Called after a restore (e.g. to refresh the menu bar indicator).
    var onRestore: (() -> Void)?

    init(tracker: WindowTracker, store: LayoutStore = LayoutStore(), settings: AppSettings) {
        self.tracker = tracker
        self.store = store
        self.settings = settings
    }

    var currentConfiguration: DisplayConfiguration { observer.current }

    var savedWindowCount: Int {
        store.layout(for: DisplayConfiguration.current().key)?.windows.count ?? 0
    }

    var savedConfigurationCount: Int { store.layouts.count }

    func start() {
        observer.onWillChange = { [weak self] in
            guard let self else { return }
            self.snapshot(reason: "display change begins", force: true)
            self.snapshotsSuspended = true
        }
        observer.onSettled = { [weak self] configuration, changed in
            self?.displaysSettled(configuration, changed: changed)
        }
        observer.start()

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] _ in self?.snapshot(reason: "app activated")
            },
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in self?.snapshot(reason: "sleep", force: true)
            },
        ]
        // Safety net for windows moved without switching apps. Generous tolerance lets
        // macOS coalesce the wake-ups with other timers.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.snapshot(reason: "timer")
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        snapshot(reason: "launch", force: true)
    }

    func stop() {
        snapshot(reason: "quit", force: true)
        observer.stop()
        timer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    /// Saves the current frames for the current display configuration.
    /// Throttled to one snapshot per 5 s unless `force` is set.
    func snapshot(reason: String, force: Bool = false) {
        guard !snapshotsSuspended, AX.isTrusted else { return }
        guard force || Date().timeIntervalSince(lastSnapshot) >= 5 else { return }
        lastSnapshot = Date()

        let configuration = DisplayConfiguration.current()
        // Displays changed but the change has not settled yet (or the "begin" callback
        // never came): windows may be mid-shuffle, don't record them.
        guard !configuration.displays.isEmpty, configuration.key == observer.current.key else { return }
        let windows = tracker.orderedWindows(includeExcluded: true)
        let saved = Self.indexed(windows).map { window, index in
            SavedWindow(bundleID: window.bundleID ?? "", title: window.title, indexInApp: index, frame: window.frame)
        }.filter { !$0.bundleID.isEmpty }
        guard !saved.isEmpty else { return }
        store.merge(saved, summary: configuration.summary, for: configuration.key)
        log.debug("Snapshot (\(reason)): \(saved.count) windows for \(configuration.summary)")
    }

    /// Moves windows back to the frames remembered for the current configuration.
    @discardableResult
    func restore() -> Int {
        guard AX.isTrusted else { return 0 }
        let configuration = DisplayConfiguration.current()
        guard let layout = store.layout(for: configuration.key) else { return 0 }
        let windows = tracker.orderedWindows(includeExcluded: true)
        let live = Self.indexed(windows).compactMap { window, index -> LayoutMatcher.LiveWindow? in
            guard let bundleID = window.bundleID else { return nil }
            return LayoutMatcher.LiveWindow(id: window.id, bundleID: bundleID, title: window.title, indexInApp: index)
        }
        let targets = LayoutMatcher.match(live: live, saved: layout.windows)
        var moved = 0
        for window in windows {
            guard let frame = targets[window.id], !Self.approximatelyEqual(frame, window.frame) else { continue }
            AX.setFrame(window.element, frame)
            moved += 1
        }
        log.info("Restored \(moved) windows for \(configuration.summary)")
        onRestore?()
        return moved
    }

    func clearAll() {
        store.removeAll()
    }

    // MARK: - Display changes

    private func displaysSettled(_ configuration: DisplayConfiguration, changed: Bool) {
        restoreWork.forEach { $0.cancel() }
        restoreWork.removeAll()
        guard changed, settings.autoRestoreLayout, store.layout(for: configuration.key) != nil else {
            snapshotsSuspended = false
            return
        }
        // Two passes: some apps (and macOS itself) move windows again a few seconds after
        // a monitor appears; the second pass only touches windows that drifted.
        for (delay, isLast) in [(0.3, false), (3.0, true)] {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.restore()
                if isLast {
                    self.snapshotsSuspended = false
                    self.lastSnapshot = Date()
                }
            }
            restoreWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Helpers

    /// Pairs each window with its index among the same app's windows, by window ID
    /// (≈ creation order), which is stable while the app runs.
    private static func indexed(_ windows: [TrackedWindow]) -> [(TrackedWindow, Int)] {
        var result: [(TrackedWindow, Int)] = []
        for (_, appWindows) in Dictionary(grouping: windows, by: { $0.bundleID ?? "" }) {
            for (index, window) in appWindows.sorted(by: { $0.id < $1.id }).enumerated() {
                result.append((window, index))
            }
        }
        return result
    }

    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 &&
            abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}
