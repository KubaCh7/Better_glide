import AppKit

/// Turns swipes into "focus the next/previous window in spatial order".
final class WindowSwitcher {
    struct Position: Equatable {
        let index: Int   // 0-based
        let count: Int
    }

    let tracker: WindowTracker
    private let settings: AppSettings
    private let overlay = HighlightOverlay()

    /// Called after a successful switch (main thread).
    var onSwitch: ((TrackedWindow) -> Void)?

    init(tracker: WindowTracker, settings: AppSettings) {
        self.tracker = tracker
        self.settings = settings
    }

    func handle(_ swipe: SwipeDirection) {
        guard settings.isEnabled else { return }
        // Natural (Spaces-like): moving the fingers left reveals what is on the right.
        let step: WindowStep
        switch (settings.direction, swipe) {
        case (.natural, .left), (.inverted, .right): step = .next
        case (.natural, .right), (.inverted, .left): step = .previous
        }
        move(step)
    }

    func move(_ step: WindowStep) {
        let windows = tracker.orderedWindows()
        let focused = tracker.focusedWindowID()
        let current = windows.firstIndex { $0.id == focused }
        guard let target = step.target(from: current, count: windows.count, wrap: settings.wrapAround) else {
            // At an edge: a light haptic "bump" instead of doing nothing silently.
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }
        focus(windows[target], slideFrom: step == .next ? 40 : -40)
    }

    func focus(_ window: TrackedWindow, slideFrom offset: CGFloat = 0) {
        tracker.focus(window)
        if settings.showHighlight {
            overlay.flash(frame: window.frame, slideFrom: offset)
        }
        onSwitch?(window)
    }

    /// Position of the focused window in the spatial order, for the menu bar indicator.
    func currentPosition() -> Position? {
        let windows = tracker.orderedWindows()
        guard let focused = tracker.focusedWindowID(),
              let index = windows.firstIndex(where: { $0.id == focused }) else { return nil }
        return Position(index: index, count: windows.count)
    }
}
