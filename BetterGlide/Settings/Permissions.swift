import AppKit
import IOKit.hid
import ScreenCaptureKit
import ServiceManagement

/// Permission checks and deep links into System Settings → Privacy & Security.
enum Permissions {
    static var accessibilityGranted: Bool { AX.isTrusted }

    /// Input Monitoring. MultitouchSupport normally works without it, but some macOS
    /// versions/configurations gate raw HID access behind it, so it is offered as optional.
    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Screen Recording: needed only for the sliding animation (snapshots of the screen).
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// On recent macOS, `CGRequestScreenCaptureAccess` alone often does not add the app to
    /// the Screen Recording list (so there is no switch to turn on). A real ScreenCaptureKit
    /// request does: it shows the system prompt and registers BetterGlide in the list.
    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            // A tiny real capture, in case listing content alone did not register the app.
            guard let display = content?.displays.first else { return }
            let config = SCStreamConfiguration()
            config.width = 2
            config.height = 2
            let filter = SCContentFilter(display: display, excludingWindows: [])
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { _, _ in }
        }
        // Give the system prompt a moment, then show the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    /// Fallback when BetterGlide still is not in the list: show the app in Finder so it can
    /// be dragged into the list (or picked with the + button).
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// macOS applies a newly granted Screen Recording permission only after a relaunch.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Removes BetterGlide's entries from the privacy database (only its own, by bundle ID).
    /// Needed when the switch in System Settings belongs to an older signature of the app:
    /// it then shows as "on" but does not apply. The next request adds a fresh entry.
    static func resetEntries(_ services: [String] = ["Accessibility", "ScreenCapture"]) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for service in services {
            Shell.run("/usr/bin/tccutil", ["reset", service, bundleID])
        }
    }

    /// "Switch is on but BetterGlide does not see it": clear the stale entry and ask again.
    static func repairAccessibility() {
        resetEntries(["Accessibility"])
        requestAccessibility()
    }

    static func repairScreenRecording() {
        resetEntries(["ScreenCapture"])
        requestScreenRecording()
    }

    static func requestAccessibility() {
        AX.requestTrust()
        openPrivacyPane("Privacy_Accessibility")
    }

    static func requestInputMonitoring() {
        // Registers the app in the list (and shows the system prompt the first time).
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openPrivacyPane("Privacy_ListenEvent")
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Launch at login via `SMAppService` (macOS 13+). Works best when the app lives in /Applications.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
