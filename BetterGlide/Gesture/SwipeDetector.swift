import Foundation

/// Physical direction the fingers moved on the trackpad.
enum SwipeDirection: String {
    case left, right
}

/// Continuous horizontal swipe, like the system's Spaces gesture.
/// `dx` is the finger travel since touch-down in trackpad widths (negative = left).
enum SwipeEvent: Equatable {
    /// Exactly `fingerCount` fingers touched down (a swipe may follow).
    case armed
    /// Movement exceeded the slop and is mostly horizontal: the swipe is tracking.
    case began
    case changed(dx: Float)
    /// Fingers lifted. `velocity` is in trackpad widths per second.
    case ended(dx: Float, velocity: Float)
    /// Not a horizontal swipe after all (vertical, more fingers, finger lifted early).
    case cancelled
}

struct SwipeConfiguration: Equatable {
    /// Exact number of fingers that must be touching (3 or 4).
    var fingerCount: Int = 3
    /// Travel (fraction of trackpad width) before the axis is decided.
    var slop: Float = 0.015
    /// Horizontal travel must dominate vertical travel by this factor.
    var directionRatio: Float = 1.2
}

/// Turns raw multitouch frames into a tracked horizontal swipe.
///
/// Pure state machine without AppKit, unit-tested. Rules:
/// - `fingerCount` fingers down → `.armed`; the finger centroid is the anchor,
/// - first significant movement decides the axis: horizontal → `.began`, vertical → ignored
///   (so a 3-finger Mission Control swipe up never starts a window switch),
/// - while tracking, every frame produces `.changed`; the first lifted finger produces `.ended`,
/// - more fingers than `fingerCount` cancel the sequence until all fingers lift.
final class SwipeDetector {
    struct Point: Equatable {
        var x: Float
        var y: Float
    }

    private enum State { case idle, armed, tracking, ignoring }

    var configuration: SwipeConfiguration

    private var state = State.idle
    private var anchor = Point(x: 0, y: 0)
    private var samples: [(time: Double, dx: Float)] = []

    init(configuration: SwipeConfiguration = SwipeConfiguration()) {
        self.configuration = configuration
    }

    /// Feed one frame of touching fingers.
    func process(touching points: [Point], timestamp: Double) -> [SwipeEvent] {
        let count = points.count
        let required = configuration.fingerCount

        if count == 0 {
            defer { reset() }
            switch state {
            case .armed: return [.cancelled]
            case .tracking: return [ended()]
            case .idle, .ignoring: return []
            }
        }
        if count > required {
            let wasActive = state == .armed || state == .tracking
            state = .ignoring
            return wasActive ? [.cancelled] : []
        }

        switch state {
        case .ignoring:
            return []

        case .idle:
            guard count == required else { return [] }
            anchor = centroid(points)
            samples.removeAll()
            state = .armed
            return [.armed]

        case .armed:
            guard count == required else {
                state = .ignoring
                return [.cancelled]
            }
            let c = centroid(points)
            let dx = c.x - anchor.x
            let dy = c.y - anchor.y
            guard max(abs(dx), abs(dy)) >= configuration.slop else { return [] }
            guard abs(dx) >= configuration.directionRatio * abs(dy) else {
                state = .ignoring
                return [.cancelled]
            }
            state = .tracking
            record(timestamp, dx)
            return [.began, .changed(dx: dx)]

        case .tracking:
            guard count == required else {
                // Fingers never lift in the same frame; end on the first one.
                state = .ignoring
                return [ended()]
            }
            let dx = centroid(points).x - anchor.x
            record(timestamp, dx)
            return [.changed(dx: dx)]
        }
    }

    func reset() {
        state = .idle
        samples.removeAll()
    }

    private func centroid(_ points: [Point]) -> Point {
        let n = Float(points.count)
        return Point(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
    }

    private func record(_ time: Double, _ dx: Float) {
        samples.append((time, dx))
        samples.removeAll { time - $0.time > 0.15 }
    }

    /// Velocity over the last ~80 ms of movement.
    private func ended() -> SwipeEvent {
        guard let last = samples.last else { return .ended(dx: 0, velocity: 0) }
        let reference = samples.first { last.time - $0.time <= 0.08 } ?? last
        let dt = last.time - reference.time
        let velocity = dt > 0.005 ? (last.dx - reference.dx) / Float(dt) : 0
        return .ended(dx: last.dx, velocity: velocity)
    }
}
