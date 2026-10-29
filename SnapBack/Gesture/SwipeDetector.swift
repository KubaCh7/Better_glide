import Foundation

/// Physical direction the fingers moved on the trackpad.
enum SwipeDirection: String {
    case left, right
}

struct SwipeConfiguration: Equatable {
    /// Exact number of fingers that must be touching (3 or 4).
    var fingerCount: Int = 3
    /// Horizontal travel of the finger centroid, as a fraction of trackpad width.
    var threshold: Float = 0.12
    /// Horizontal travel must dominate vertical travel by this factor.
    var directionRatio: Float = 1.5
    /// Minimum time between two recognized swipes (debounce), in seconds.
    var cooldown: Double = 0.35
}

/// Turns raw multitouch frames into discrete left/right swipes.
///
/// Pure state machine with no AppKit dependencies so it can be unit-tested.
/// Rules:
/// - a gesture starts when exactly `fingerCount` fingers touch; the centroid is the anchor,
/// - it fires once when the centroid moved past `threshold` mostly horizontally,
/// - it fires at most once per touch sequence (until all fingers lift),
/// - if more fingers than `fingerCount` touch, the sequence is ignored until lift-off
///   (so a 4-finger swipe never triggers the 3-finger action while fingers land/lift),
/// - a cooldown debounces quick repeated swipes.
final class SwipeDetector {
    struct Point: Equatable {
        var x: Float
        var y: Float
    }

    var configuration: SwipeConfiguration

    private var anchor: Point?
    private var firedInSequence = false
    private var sequenceBlocked = false
    private var lastFireTime = -Double.infinity

    init(configuration: SwipeConfiguration = SwipeConfiguration()) {
        self.configuration = configuration
    }

    /// Feed one frame of touching fingers. Returns a direction when a swipe is recognized.
    func process(touching points: [Point], timestamp: Double) -> SwipeDirection? {
        let n = points.count

        if n == 0 {
            reset()
            return nil
        }
        if n > configuration.fingerCount {
            sequenceBlocked = true
            anchor = nil
            return nil
        }
        guard n == configuration.fingerCount, !sequenceBlocked, !firedInSequence else {
            // Wrong finger count (e.g. fingers still landing): re-anchor once it is right.
            if n != configuration.fingerCount { anchor = nil }
            return nil
        }

        let centroid = Point(
            x: points.reduce(0) { $0 + $1.x } / Float(n),
            y: points.reduce(0) { $0 + $1.y } / Float(n)
        )
        guard let start = anchor else {
            anchor = centroid
            return nil
        }

        let dx = centroid.x - start.x
        let dy = centroid.y - start.y
        guard abs(dx) >= configuration.threshold,
              abs(dx) >= configuration.directionRatio * abs(dy),
              timestamp - lastFireTime >= configuration.cooldown
        else { return nil }

        firedInSequence = true
        lastFireTime = timestamp
        return dx > 0 ? .right : .left
    }

    func reset() {
        anchor = nil
        firedInSequence = false
        sequenceBlocked = false
    }
}
