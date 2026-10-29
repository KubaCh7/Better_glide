import AppKit
import ScreenCaptureKit

/// Captures what the slide animation shows: the visible area of a display ("current
/// page") and individual windows (to compose the "next page" with that window on top).
///
/// Uses ScreenCaptureKit (requires the Screen Recording permission). Captures run only
/// when a horizontal swipe starts, in parallel, typically in a few dozen milliseconds.
final class ScreenSnapshotter {
    struct Request {
        var displays: [DisplayGeometry]
        var windows: [(id: CGWindowID, size: CGSize, scale: CGFloat)]
    }

    struct Result {
        var displays: [CGDirectDisplayID: CGImage] = [:]
        var windows: [CGWindowID: CGImage] = [:]
    }

    static var isPermitted: Bool { CGPreflightScreenCaptureAccess() }

    /// Calls `completion` on the main thread (with whatever could be captured).
    func capture(_ request: Request, completion: @escaping (Result) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            guard let content else {
                DispatchQueue.main.async { completion(Result()) }
                return
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            // Never capture our own overlay (e.g. while a previous slide is fading out).
            let ownApps = content.applications.filter { $0.processID == ownPID }
            let group = DispatchGroup()
            let lock = NSLock()
            var result = Result()

            for geometry in request.displays {
                guard let display = content.displays.first(where: { $0.displayID == geometry.displayID }) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = geometry.sourceRect
                config.width = Int(geometry.sourceRect.width * geometry.scale)
                config.height = Int(geometry.sourceRect.height * geometry.scale)
                config.showsCursor = false
                config.captureResolution = .best
                group.enter()
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    if let image {
                        lock.lock()
                        result.displays[geometry.displayID] = image
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            for window in request.windows {
                guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = Int(window.size.width * window.scale)
                config.height = Int(window.size.height * window.scale)
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                config.captureResolution = .best
                group.enter()
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    if let image {
                        lock.lock()
                        result.windows[window.id] = image
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { completion(result) }
        }
    }
}
