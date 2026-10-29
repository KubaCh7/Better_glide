import XCTest

final class SwipeDetectorTests: XCTestCase {
    private func fingers(_ n: Int, x: Float, y: Float = 0.5) -> [SwipeDetector.Point] {
        (0..<n).map { SwipeDetector.Point(x: x + Float($0) * 0.05, y: y) }
    }

    private func detector(_ fingerCount: Int = 3) -> SwipeDetector {
        SwipeDetector(configuration: SwipeConfiguration(fingerCount: fingerCount))
    }

    func testTracksHorizontalSwipeAndEndsWithVelocity() {
        let d = detector()
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.5), timestamp: 0), [.armed])
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.505), timestamp: 0.01), []) // within slop
        let began = d.process(touching: fingers(3, x: 0.45), timestamp: 0.02)
        XCTAssertEqual(began.first, .began)
        guard case .changed(let dx)? = began.last else { return XCTFail("expected changed") }
        XCTAssertEqual(dx, -0.05, accuracy: 0.0001)
        _ = d.process(touching: fingers(3, x: 0.35), timestamp: 0.06)

        // First finger lifting ends the swipe.
        let end = d.process(touching: fingers(2, x: 0.35), timestamp: 0.07)
        guard case .ended(let endDx, let velocity)? = end.first else { return XCTFail("expected ended") }
        XCTAssertEqual(endDx, -0.15, accuracy: 0.0001)
        XCTAssertEqual(velocity, -2.5, accuracy: 0.01) // -0.1 over 0.04 s
        XCTAssertEqual(d.process(touching: [], timestamp: 0.08), [])
    }

    func testVerticalMovementIsNotASwipe() {
        let d = detector()
        _ = d.process(touching: fingers(3, x: 0.5, y: 0.3), timestamp: 0)
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.51, y: 0.4), timestamp: 0.02), [.cancelled])
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.2, y: 0.4), timestamp: 0.04), [])
    }

    func testWrongFingerCountIgnored() {
        let d = detector()
        XCTAssertEqual(d.process(touching: fingers(2, x: 0.3), timestamp: 0), [])
        XCTAssertEqual(d.process(touching: fingers(2, x: 0.6), timestamp: 0.05), [])
    }

    func testExtraFingerCancelsUntilLiftOff() {
        let d = detector()
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 0)
        _ = d.process(touching: fingers(3, x: 0.4), timestamp: 0.02)
        XCTAssertEqual(d.process(touching: fingers(4, x: 0.4), timestamp: 0.03), [.cancelled])
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.6), timestamp: 0.04), [])
        XCTAssertEqual(d.process(touching: [], timestamp: 0.1), [])
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.3), timestamp: 1.0), [.armed])
    }

    func testFourFingerConfiguration() {
        let d = detector(4)
        XCTAssertEqual(d.process(touching: fingers(3, x: 0.3), timestamp: 0), [])
        XCTAssertEqual(d.process(touching: fingers(4, x: 0.3), timestamp: 0.01), [.armed])
        XCTAssertEqual(d.process(touching: fingers(4, x: 0.4), timestamp: 0.02).first, .began)
    }

    func testLiftBeforeMovingCancels() {
        let d = detector()
        _ = d.process(touching: fingers(3, x: 0.3), timestamp: 0)
        XCTAssertEqual(d.process(touching: [], timestamp: 0.05), [.cancelled])
    }
}
