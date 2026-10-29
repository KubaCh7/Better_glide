import AppKit
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let gestureMonitor = GestureMonitor()
    private let tracker = WindowTracker()
    private lazy var switcher = WindowSwitcher(tracker: tracker, settings: settings)
    private lazy var layoutManager = LayoutManager(tracker: tracker, settings: settings)
    private var menuBar: MenuBarController?
    private let windows = WindowPresenter()
    private let gestureFeed = GestureFeed()
    private var activationObserver: NSObjectProtocol?
    private var indicatorRefresh: DispatchWorkItem?
    private let log = Logger(subsystem: "com.betterglide.BetterGlide", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global AX timeout: an unresponsive app must never block the main thread for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

        menuBar = MenuBarController(settings: settings, switcher: switcher, actions: .init(
            saveLayout: { [weak self] in self?.layoutManager.snapshot(reason: "menu", force: true) },
            restoreLayout: { [weak self] in self?.layoutManager.restore() },
            savedWindowCount: { [weak self] in self?.layoutManager.savedWindowCount ?? 0 },
            openSettings: { [weak self] in self?.showSettings() },
            openOnboarding: { [weak self] in self?.showOnboarding() }
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
            self?.gestureFeed.last = GestureFeed.Event(direction: direction, date: Date())
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

        if !settings.hasCompletedOnboarding || !AX.isTrusted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureMonitor.stop()
        layoutManager.stop()
    }

    private func applySettings() {
        tracker.excludedBundleIDs = Set(settings.excludedBundleIDs)
        gestureMonitor.update(configuration: settings.swipeConfiguration)
        // Debounced: dragging the sensitivity slider fires many changes in a row.
        indicatorRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.menuBar?.refreshIndicator() }
        indicatorRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Windows

    private func showSettings() {
        windows.show(id: "settings", title: "Ustawienia BetterGlide") {
            SettingsView(
                settings: settings,
                feed: gestureFeed,
                savedConfigurationCount: { [weak self] in self?.layoutManager.savedConfigurationCount ?? 0 },
                clearLayouts: { [weak self] in self?.layoutManager.clearAll() }
            )
        }
    }

    private func showOnboarding() {
        windows.show(id: "onboarding", title: "BetterGlide — konfiguracja") {
            OnboardingView(
                settings: settings,
                feed: gestureFeed,
                gesturesAvailable: gestureMonitor.isAvailable,
                onDone: { [weak self] in
                    self?.windows.close(id: "onboarding")
                    self?.menuBar?.refreshIndicator()
                }
            )
        }
    }
}
