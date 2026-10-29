import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gestureMonitor = GestureMonitor()
    private let log = Logger(subsystem: "com.snapback.SnapBack", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stage (a): just log recognized swipes.
        gestureMonitor.onSwipe = { [log] direction in
            log.info("Swipe \(direction.rawValue)")
        }
        gestureMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureMonitor.stop()
    }
}
