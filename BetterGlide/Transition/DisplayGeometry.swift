import AppKit

/// The part of a display the slide animation covers: everything except the menu bar
/// and the Dock, which stay in place (as they do when switching Spaces).
struct DisplayGeometry: Equatable {
    let displayID: CGDirectDisplayID
    /// Cocoa coordinates (bottom-left origin) — frame of the overlay window.
    let visibleFrame: CGRect
    /// Same area in global CG coordinates (top-left origin, like window frames).
    let cgVisibleRect: CGRect
    /// Same area in display-local points, for ScreenCaptureKit's `sourceRect`.
    let sourceRect: CGRect
    let scale: CGFloat

    init?(displayID: CGDirectDisplayID) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }) else { return nil }
        let bounds = CGDisplayBounds(displayID)
        let visible = screen.visibleFrame
        let top = screen.frame.maxY - visible.maxY // menu bar height
        self.displayID = displayID
        visibleFrame = visible
        sourceRect = CGRect(x: visible.minX - screen.frame.minX, y: top,
                            width: visible.width, height: visible.height)
        cgVisibleRect = sourceRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
        scale = screen.backingScaleFactor
    }

    /// `rect` (global CG coordinates) relative to this area, in bottom-left layer coordinates.
    func layerRect(for rect: CGRect) -> CGRect {
        let x = rect.minX - cgVisibleRect.minX
        let topOffset = rect.minY - cgVisibleRect.minY
        return CGRect(x: x, y: cgVisibleRect.height - topOffset - rect.height, width: rect.width, height: rect.height)
    }

    /// Display that shows most of `rect` (global CG coordinates).
    static func displayID(containing rect: CGRect) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return ids.prefix(Int(count)).max { a, b in
            area(CGDisplayBounds(a).intersection(rect)) < area(CGDisplayBounds(b).intersection(rect))
        }.flatMap { best in
            area(CGDisplayBounds(best).intersection(rect)) > 0 ? best : ids.first { CGDisplayBounds($0).contains(center) }
        }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
