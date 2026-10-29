import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let gestureMonitor = GestureMonitor()
    private let tracker = WindowTracker()
    private lazy var switcher = WindowSwitcher(tracker: tracker, settings: settings)
    private lazy var layoutManager = LayoutManager(tracker: tracker, settings: settings)
    private var menuBar: MenuBarController?
    private var activationObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.snapback.SnapBack", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global AX timeout: an unresponsive app must never block the main thread for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        if !AX.isTrusted { AX.requestTrust() }

        menuBar = MenuBarController(settings: settings, switcher: switcher, actions: .init(
            saveLayout: { [weak self] in self?.layoutManager.snapshot(reason: "menu", force: true) },
            restoreLayout: { [weak self] in self?.layoutManager.restore() },
            savedWindowCount: { [weak self] in self?.layoutManager.savedWindowCount ?? 0 },
            openSettings: {},
            openOnboarding: { Permissions.requestAccessibility() }
        ))

        applySettings()
        settings.onChange = { [weak self] in self?.applySettings() }

        switcher.onSwitch = { [weak self] _ in
            self?.menuBar?.refreshIndicator()
            self?.layoutManager.snapshot(reason: "switch")
        }
        layoutManager.onRestore = { [weak self] in self?.menuBar?.refreshIndicator() }
        layoutManager.start()
        gestureMonitor.onSwipe = { [weak self] direction in
            self?.switcher.handle(direction)
        }
        gestureMonitor.start()

        // Keep the "2/3" indicator current when focus changes by other means (click, Cmd+Tab).
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.menuBar?.refreshIndicator()
        }
        menuBar?.refreshIndicator()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureMonitor.stop()
        layoutManager.stop()
    }

    private func applySettings() {
        tracker.excludedBundleIDs = Set(settings.excludedBundleIDs)
        gestureMonitor.update(configuration: settings.swipeConfiguration)
        menuBar?.refreshIndicator()
    }
}
