import CoreGraphics
import Foundation

/// Identifies a monitor setup: which displays (vendor/model/serial), their resolution
/// and their arrangement. Layouts are stored per `key`.
struct DisplayConfiguration: Equatable {
    struct Display: Equatable {
        var vendor: UInt32
        var model: UInt32
        var serial: UInt32
        var pixelWidth: Int
        var pixelHeight: Int
        /// Global bounds in points, top-left origin.
        var bounds: CGRect
        var isBuiltin: Bool

        var fingerprint: String {
            "\(vendor)-\(model)-\(serial)@\(pixelWidth)x\(pixelHeight)" +
                "[\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width))x\(Int(bounds.height))]"
        }
    }

    var displays: [Display]

    /// Order-independent, stable identifier of this configuration.
    var key: String {
        displays.map(\.fingerprint).sorted().joined(separator: "|")
    }

    /// Short human-readable description, e.g. "Wbudowany 1512×982 + 2560×1440".
    var summary: String {
        displays
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map { ($0.isBuiltin ? "Wbudowany " : "") + "\(Int($0.bounds.width))×\(Int($0.bounds.height))" }
            .joined(separator: " + ")
    }

    /// The current setup, ignoring secondary displays of a mirror set.
    static func current() -> DisplayConfiguration {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return DisplayConfiguration(displays: [])
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return DisplayConfiguration(displays: [])
        }
        let displays = ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id -> Display in
                let mode = CGDisplayCopyDisplayMode(id)
                return Display(
                    vendor: CGDisplayVendorNumber(id),
                    model: CGDisplayModelNumber(id),
                    serial: CGDisplaySerialNumber(id),
                    pixelWidth: mode?.pixelWidth ?? CGDisplayPixelsWide(id),
                    pixelHeight: mode?.pixelHeight ?? CGDisplayPixelsHigh(id),
                    bounds: CGDisplayBounds(id),
                    isBuiltin: CGDisplayIsBuiltin(id) != 0
                )
            }
        return DisplayConfiguration(displays: displays)
    }
}
