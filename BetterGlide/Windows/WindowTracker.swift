import AppKit
import os

/// A switchable window on the current Space.
struct TrackedWindow {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let title: String
    /// Global coordinates, top-left origin (CGWindowList / Accessibility space).
    let frame: CGRect
    let element: AXUIElement

    var displayTitle: String {
        title.isEmpty ? appName : "\(appName) — \(title)"
    }
}

/// Discovers switchable windows and keeps their spatial order stable.
///
/// Nothing is polled: the list is rebuilt on demand (gesture, menu opening, layout
/// snapshot), which costs a few milliseconds of Accessibility IPC per call.
final class WindowTracker {
    /// Bundle IDs that are never switched to.
    var excludedBundleIDs: Set<String> = []

    /// First-seen rank per window; used as the stable tie-breaker in `WindowOrdering`.
    private var ranks: [CGWindowID: Int] = [:]
    private var nextRank = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let log = Logger(subsystem: "com.betterglide.BetterGlide", category: "windows")

    private struct CGEntry {
        let pid: pid_t
        let bounds: CGRect
        let zIndex: Int
    }

    /// Switchable windows on the current Space, in spatial order.
    func orderedWindows(includeExcluded: Bool = false) -> [TrackedWindow] {
        let windows = currentWindows(includeExcluded: includeExcluded)
        let byID = Dictionary(windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { a, _ in a })

        // Seed ranks for new windows in z-order (frontmost first).
        for entry in windows.sorted(by: { $0.zIndex < $1.zIndex }) where ranks[entry.window.id] == nil {
            ranks[entry.window.id] = nextRank
            nextRank += 1
        }
        if !includeExcluded {
            // Forget closed windows so the map does not grow forever.
            ranks = ranks.filter { byID[$0.key] != nil }
        }

        let items = windows.map {
            WindowOrdering.Item(id: $0.window.id, frame: $0.window.frame, rank: ranks[$0.window.id] ?? Int.max)
        }
        return WindowOrdering.sorted(items, displays: Self.displayBounds()).compactMap { byID[$0] }
    }

    /// The focused window of the frontmost app, if it is one of `windows`.
    func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute) else { return nil }
        return AX.windowID(window)
    }

    /// Raises and focuses a specific window (also when it is not the app's main window).
    func focus(_ window: TrackedWindow) {
        let axApp = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        // Make it the app's main window first, so activating the app brings *this* window.
        AX.setBool(window.element, kAXMainAttribute, true)
        let frontmostSet = AX.setBool(axApp, kAXFrontmostAttribute, true)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)

        if !frontmostSet, let app = NSRunningApplication(processIdentifier: window.pid) {
            // Fallback; on macOS 14+ activation from a background app is "cooperative"
            // and may be refused, which is why the AX route above is preferred.
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    /// Global bounds of active displays (top-left origin), excluding mirrored secondaries.
    static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { CGDisplayBounds($0) }
    }

    // MARK: - Discovery

    private func currentWindows(includeExcluded: Bool) -> [(window: TrackedWindow, zIndex: Int)] {
        guard AX.isTrusted else { return [] }
        let cgWindows = onScreenWindows()
        guard !cgWindows.isEmpty else { return [] }

        var result: [(window: TrackedWindow, zIndex: Int)] = []
        let pids = Set(cgWindows.values.map(\.pid))
        for pid in pids where pid != ownPID {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, !app.isHidden else { continue }
            if !includeExcluded, let bundleID = app.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
                continue
            }
            let axApp = AXUIElementCreateApplication(pid)
            // A hung app must not stall the gesture.
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            for element in AX.elements(axApp, kAXWindowsAttribute) {
                guard isStandardWindow(element),
                      let id = AX.windowID(element),
                      let cg = cgWindows[id] // on screen ⇒ current Space, not minimized
                else { continue }
                let window = TrackedWindow(
                    id: id,
                    pid: pid,
                    bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "?",
                    title: AX.string(element, kAXTitleAttribute) ?? "",
                    frame: cg.bounds,
                    element: element
                )
                result.append((window: window, zIndex: cg.zIndex))
            }
        }
        return result
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard AX.string(element, kAXRoleAttribute) == kAXWindowRole,
              AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
        else { return false }
        return AX.bool(element, kAXMinimizedAttribute) != true
    }

    /// Normal-layer windows that are on screen, keyed by window ID, with their z-index
    /// (0 = frontmost). "On screen only" also limits the list to the current Space.
    private func onScreenWindows() -> [CGWindowID: CGEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [CGWindowID: CGEntry] = [:]
        for (z, window) in info.enumerated() {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  bounds.width >= 50, bounds.height >= 50
            else { continue }
            result[id] = CGEntry(pid: pid, bounds: bounds, zIndex: z)
        }
        return result
    }
}
