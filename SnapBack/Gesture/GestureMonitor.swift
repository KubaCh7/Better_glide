import AppKit
import os

/// Bridges raw MultitouchSupport frames to discrete swipe events on the main thread.
///
/// CPU: the private framework only calls us while fingers touch the trackpad; each frame
/// is a handful of float additions, so idle cost is zero and active cost is negligible.
final class GestureMonitor {
    /// Delivered on the main thread.
    var onSwipe: (@MainActor (SwipeDirection) -> Void)?

    private let detector = SwipeDetector()
    private let lock = NSLock()
    private var pendingConfiguration: SwipeConfiguration?
    private var wakeObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.snapback.SnapBack", category: "gesture")

    var isAvailable: Bool { MultitouchBridge.isAvailable }
    private(set) var deviceCount = 0

    /// Thread-safe: applied on the multitouch thread before the next frame.
    func update(configuration: SwipeConfiguration) {
        lock.lock()
        pendingConfiguration = configuration
        lock.unlock()
    }

    func start() {
        guard MultitouchBridge.isAvailable else {
            log.error("MultitouchSupport not available; gestures disabled")
            return
        }
        MultitouchBridge.frameHandler = { [weak self] contacts, timestamp in
            self?.handle(contacts: contacts, timestamp: timestamp)
        }
        deviceCount = MultitouchBridge.start()
        log.info("Listening on \(self.deviceCount) multitouch device(s)")

        // Device handles become stale after sleep; re-enumerate on wake
        // (this also picks up a Magic Trackpad connected while asleep).
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.restart()
            }
        }
    }

    func restart() {
        deviceCount = MultitouchBridge.start()
        log.info("Restarted on \(self.deviceCount) multitouch device(s)")
    }

    func stop() {
        MultitouchBridge.stop()
        MultitouchBridge.frameHandler = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    // Runs on MultitouchSupport's private thread.
    private func handle(contacts: [MultitouchBridge.Contact], timestamp: Double) {
        lock.lock()
        if let configuration = pendingConfiguration {
            detector.configuration = configuration
            detector.reset()
            pendingConfiguration = nil
        }
        lock.unlock()

        let points = contacts.lazy.filter(\.isTouching).map { SwipeDetector.Point(x: $0.x, y: $0.y) }
        guard let direction = detector.process(touching: Array(points), timestamp: timestamp) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onSwipe?(direction)
        }
    }
}
