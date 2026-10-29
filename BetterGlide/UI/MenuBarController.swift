import AppKit

/// Status item with the spatial window list, exclusions and app controls.
/// The menu is rebuilt only when it opens (no background polling).
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var saveLayout: () -> Void
        var restoreLayout: () -> Void
        var savedWindowCount: () -> Int
        var openSettings: () -> Void
        var openOnboarding: () -> Void
        var showUpdates: () -> Void
        /// Build number of an available update, if any.
        var availableUpdate: () -> Int?
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let settings: AppSettings
    private let switcher: WindowSwitcher
    private let actions: Actions

    init(settings: AppSettings, switcher: WindowSwitcher, actions: Actions) {
        self.settings = settings
        self.switcher = switcher
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.toolTip = "BetterGlide"
        }
        updateIndicator(position: nil)
    }

    /// Updates the icon and the optional "2/3" position text.
    func updateIndicator(position: WindowSwitcher.Position?) {
        guard let button = statusItem.button else { return }
        let symbol = settings.isEnabled ? "rectangle.split.3x1" : "rectangle.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BetterGlide")
        image?.isTemplate = true
        button.image = image
        if settings.isEnabled, settings.showPositionInMenuBar, let position {
            button.title = " \(position.index + 1)/\(position.count)"
        } else {
            button.title = ""
        }
        button.appearsDisabled = !settings.isEnabled
    }

    func refreshIndicator() {
        updateIndicator(position: settings.showPositionInMenuBar ? switcher.currentPosition() : nil)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let build = actions.availableUpdate() {
            let item = addItem("Dostępna aktualizacja (build \(build))…", action: #selector(showUpdates))
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(.separator())
        }

        if !AX.isTrusted {
            let item = addItem("⚠︎ Nadaj uprawnienie Dostępności…", action: #selector(openOnboarding))
            item.toolTip = "Bez niego BetterGlide nie widzi i nie przełącza okien."
            menu.addItem(.separator())
        }

        addWindowList()
        menu.addItem(.separator())

        let toggle = addItem("Przełączanie gestem włączone", action: #selector(toggleEnabled))
        toggle.state = settings.isEnabled ? .on : .off
        menu.addItem(excludedAppsItem())
        menu.addItem(.separator())

        let saved = actions.savedWindowCount()
        let info = NSMenuItem(title: "Zapamiętany układ: \(saved) okien (ta konfiguracja ekranów)",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        addItem("Zapisz układ teraz", action: #selector(saveLayout))
        addItem("Przywróć zapamiętany układ", action: #selector(restoreLayout)).isEnabled = saved > 0
        menu.addItem(.separator())

        addItem("Ustawienia…", action: #selector(openSettings), key: ",")
        addItem("Uprawnienia i konfiguracja gestu…", action: #selector(openOnboarding))
        addItem("Sprawdź aktualizacje…", action: #selector(showUpdates))
        menu.addItem(.separator())
        addItem("Zakończ BetterGlide", action: #selector(quit), key: "q")
    }

    private func addWindowList() {
        let windows = switcher.tracker.orderedWindows()
        let focused = switcher.tracker.focusedWindowID()
        let header = NSMenuItem(title: "Okna (od lewej do prawej)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        guard !windows.isEmpty else {
            let empty = NSMenuItem(title: "Brak okien do przełączania", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let displays = WindowOrdering.sortedDisplays(WindowTracker.displayBounds())
        var lastDisplay: Int?
        for (index, window) in windows.enumerated() {
            let display = WindowOrdering.displayIndex(for: window.frame, sortedDisplays: displays)
            if displays.count > 1, display != lastDisplay {
                let label = NSMenuItem(title: "Ekran \(display + 1)", action: nil, keyEquivalent: "")
                label.isEnabled = false
                label.indentationLevel = 1
                menu.addItem(label)
                lastDisplay = display
            }
            let title = Self.truncate("\(index + 1). \(window.displayTitle)", to: 60)
            let item = addItem(title, action: #selector(focusWindow(_:)))
            item.representedObject = window.id
            item.state = window.id == focused ? .on : .off
            item.image = Self.icon(for: window.pid)
            if index < 9 {
                item.keyEquivalent = "\(index + 1)"
                item.keyEquivalentModifierMask = []
            }
        }
    }

    private struct AppEntry {
        let bundleID: String
        let name: String
        let pid: pid_t?
    }

    private func excludedAppsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Wykluczone aplikacje", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        // Running regular apps plus anything already excluded but not running.
        var apps: [AppEntry] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppEntry(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: app.processIdentifier)
            }
        let running = Set(apps.map(\.bundleID))
        apps += settings.excludedBundleIDs
            .filter { !running.contains($0) }
            .map { AppEntry(bundleID: $0, name: $0, pid: nil) }
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let hint = NSMenuItem(title: "Zaznaczone aplikacje są pomijane przy przełączaniu",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        submenu.addItem(.separator())
        for app in apps {
            let appItem = NSMenuItem(title: app.name, action: #selector(toggleExcluded(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = app.bundleID
            appItem.state = settings.isExcluded(app.bundleID) ? .on : .off
            appItem.image = app.pid.flatMap(Self.icon(for:))
            submenu.addItem(appItem)
        }
        item.submenu = submenu
        return item
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID,
              let window = switcher.tracker.orderedWindows().first(where: { $0.id == id }) else { return }
        switcher.focus(window)
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        refreshIndicator()
    }

    @objc private func toggleExcluded(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        settings.setExcluded(bundleID, !settings.isExcluded(bundleID))
        refreshIndicator()
    }

    @objc private func saveLayout() { actions.saveLayout() }
    @objc private func restoreLayout() { actions.restoreLayout() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func openOnboarding() { actions.openOnboarding() }
    @objc private func showUpdates() { actions.showUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Helpers

    private static func icon(for pid: pid_t) -> NSImage? {
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func truncate(_ string: String, to length: Int) -> String {
        string.count <= length ? string : String(string.prefix(length - 1)) + "…"
    }
}
