import AppKit
import SwiftUI

/// Shows SwiftUI content in a regular window. Needed because a menu bar (LSUIElement)
/// app has no main menu or Dock icon and must activate itself explicitly.
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    /// - Parameter glass: content draws behind a transparent title bar (Liquid Glass windows
    ///   with their own backdrop).
    func show<Content: View>(id: String, title: String, glass: Bool = false,
                             @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            bringToFront(existing)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        if glass {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.delegate = self
        window.center()
        windows[id] = window
        bringToFront(window)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        // Drop the hosting controller so SwiftUI timers stop while the window is closed.
        windows[id] = nil
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
