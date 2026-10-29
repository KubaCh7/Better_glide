import AppKit

/// Knows the spatial order and the neighbours of the focused window, and focuses windows.
final class WindowSwitcher {
    struct Position: Equatable {
        let index: Int   // 0-based
        let count: Int
    }

    /// The focused window and its neighbours in spatial order.
    struct Neighbors {
        let current: TrackedWindow?
        /// Window on the left (revealed when the content moves right).
        let previous: TrackedWindow?
        /// Window on the right (revealed when the content moves left).
        let next: TrackedWindow?
    }

    let tracker: WindowTracker
    private let settings: AppSettings
    /// Window we focused last and when. Focus changes reach the AX API asynchronously,
    /// so a quick second swipe continues from here instead of a stale focused window.
    private var lastTarget: (id: CGWindowID, date: Date)?

    /// Called after a successful switch (main thread).
    var onSwitch: ((TrackedWindow) -> Void)?

    init(tracker: WindowTracker, settings: AppSettings) {
        self.tracker = tracker
        self.settings = settings
    }

    func neighbors() -> Neighbors {
        let windows = tracker.orderedWindows()
        let index = currentIndex(in: windows)
        func window(_ step: WindowStep) -> TrackedWindow? {
            step.target(from: index, count: windows.count, wrap: settings.wrapAround).map { windows[$0] }
        }
        return Neighbors(current: index.map { windows[$0] }, previous: window(.previous), next: window(.next))
    }

    func focus(_ window: TrackedWindow) {
        tracker.focus(window)
        lastTarget = (window.id, Date())
        onSwitch?(window)
    }

    /// Position of the focused window in the spatial order, for the menu bar indicator.
    func currentPosition() -> Position? {
        let windows = tracker.orderedWindows()
        guard let index = currentIndex(in: windows) else { return nil }
        return Position(index: index, count: windows.count)
    }

    private func currentIndex(in windows: [TrackedWindow]) -> Int? {
        var focused = tracker.focusedWindowID()
        if let lastTarget, Date().timeIntervalSince(lastTarget.date) < 1.0,
           windows.contains(where: { $0.id == lastTarget.id }) {
            focused = lastTarget.id
        }
        return windows.firstIndex { $0.id == focused }
    }
}
