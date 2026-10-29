import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let gestureMonitor = GestureMonitor()
    private let tracker = WindowTracker()
    private lazy var switcher = WindowSwitcher(tracker: tracker, settings: settings)
    private let log = Logger(subsystem: "com.snapback.SnapBack", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global AX timeout: an unresponsive app must never block the main thread for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        if !AX.isTrusted { AX.requestTrust() }

        applySettings()
        settings.onChange = { [weak self] in self?.applySettings() }

        gestureMonitor.onSwipe = { [weak self] direction in
            self?.switcher.handle(direction)
        }
        gestureMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureMonitor.stop()
    }

    private func applySettings() {
        tracker.excludedBundleIDs = Set(settings.excludedBundleIDs)
        gestureMonitor.update(configuration: settings.swipeConfiguration)
    }
}
