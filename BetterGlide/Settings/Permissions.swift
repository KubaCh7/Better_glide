import AppKit
import IOKit.hid
import ServiceManagement

/// Permission checks and deep links into System Settings → Privacy & Security.
enum Permissions {
    static var accessibilityGranted: Bool { AX.isTrusted }

    /// Input Monitoring. MultitouchSupport normally works without it, but some macOS
    /// versions/configurations gate raw HID access behind it, so it is offered as optional.
    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
