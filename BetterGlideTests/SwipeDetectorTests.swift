import XCTest

final class SwipeDetectorTests: XCTestCase {
    private func fingers(_ n: Int, x: Float, y: Float = 0.5) -> [SwipeDetector.Point] {
        (0..<n).map { SwipeDetector.Point(x: x + Float($0) * 0.05, y: y) }
    }

    func testThreeFingerSwipeRight() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1))
        XCTAssertNil(d.process(touching: fingers(3, x: 0.3), timestamp: 0))
        XCTAssertNil(d.process(touching: fingers(3, x: 0.35), timestamp: 0.01))
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.45), timestamp: 0.02), .right)
        // Only once per touch sequence.
        XCTAssertNil(d.process(touching: fingers(3, x: 0.7), timestamp: 0.03))
    }

    func testSwipeLeft() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1))
        _ = d.process(touching: fingers(3, x: 0.6), timestamp: 0)
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.45), timestamp: 0.05), .left)
    }

    func testWrongFingerCountIgnored() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1))
        _ = d.process(touching: fingers(2, x: 0.3), timestamp: 0)
        XCTAssertNil(d.process(touching: fingers(2, x: 0.6), timestamp: 0.05))
    }

    func testMoreFingersBlocksSequenceUntilLiftOff() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1))
        _ = d.process(touching: fingers(4, x: 0.3), timestamp: 0)
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 0.01)
        XCTAssertNil(d.process(touching: fingers(3, x: 0.6), timestamp: 0.05))
        _ = d.process(touching: [], timestamp: 0.1)
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 1.0)
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.6), timestamp: 1.05), .right)
    }

    func testVerticalMovementIgnored() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1))
        _ = d.process(touching: fingers(3, x: 0.3, y: 0.2), timestamp: 0)
        XCTAssertNil(d.process(touching: fingers(3, x: 0.42, y: 0.6), timestamp: 0.05))
    }

    func testCooldownDebounces() {
        let d = SwipeDetector(configuration: SwipeConfiguration(fingerCount: 3, threshold: 0.1, cooldown: 0.5))
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 0)
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.5), timestamp: 0.05), .right)
        _ = d.process(touching: [], timestamp: 0.1)
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 0.15)
        XCTAssertNil(d.process(touching: fingers(3, x: 0.5), timestamp: 0.2))
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.5), timestamp: 0.6), .right)
    }
}
