import CoreGraphics

/// Pure math for the Spaces-like slide. Unit-tested.
///
/// Sign convention: `progress` is the content offset in page widths. Negative means the
/// current page moved left, revealing the page on the right (the next window).
enum SlideMath {
    /// Velocity (pages per second) that counts as a flick.
    static let flickVelocity: CGFloat = 0.6
    /// Distance (fraction of a page) that commits a slow drag.
    static let commitDistance: CGFloat = 0.35

    /// Whether lifting the fingers should complete the switch.
    static func shouldCommit(progress: CGFloat, velocity: CGFloat) -> Bool {
        guard progress != 0 else { return false }
        if abs(velocity) >= flickVelocity {
            // A flick decides, but only towards the side that is actually revealed.
            return (velocity < 0) == (progress < 0) && abs(progress) > 0.02
        }
        return abs(progress) >= commitDistance
    }

    /// Resistance when dragging past the last window (iOS-style rubber band).
    static func rubberBand(_ offset: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        let distance = abs(offset)
        let result = (1 - 1 / (distance * coefficient / dimension + 1)) * dimension
        return offset < 0 ? -result : result
    }

    /// Content progress (page widths) for a finger travel `dx` (trackpad widths).
    /// Natural direction: content follows the fingers, like Spaces.
    static func progress(fingerTravel dx: CGFloat, gain: CGFloat, natural: Bool) -> CGFloat {
        let value = dx * gain * (natural ? 1 : -1)
        return min(max(value, -1), 1)
    }
}
