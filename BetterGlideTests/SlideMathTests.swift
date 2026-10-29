import XCTest

final class SlideMathTests: XCTestCase {
    func testSlowDragCommitsPastDistance() {
        XCTAssertFalse(SlideMath.shouldCommit(progress: -0.2, velocity: -0.1))
        XCTAssertTrue(SlideMath.shouldCommit(progress: -0.4, velocity: -0.1))
        XCTAssertTrue(SlideMath.shouldCommit(progress: 0.4, velocity: 0))
    }

    func testFlickCommitsEvenWhenShort() {
        XCTAssertTrue(SlideMath.shouldCommit(progress: -0.1, velocity: -1.5))
        XCTAssertTrue(SlideMath.shouldCommit(progress: 0.1, velocity: 1.5))
    }

    func testFlickBackCancels() {
        XCTAssertFalse(SlideMath.shouldCommit(progress: -0.5, velocity: 1.5))
    }

    func testNoMovementNeverCommits() {
        XCTAssertFalse(SlideMath.shouldCommit(progress: 0, velocity: -3))
    }

    func testRubberBandResistsAndKeepsSign() {
        let width: CGFloat = 1000
        let pulled = SlideMath.rubberBand(-500, dimension: width)
        XCTAssertLessThan(pulled, 0)
        XCTAssertLessThan(abs(pulled), 500)
        XCTAssertLessThan(abs(SlideMath.rubberBand(5000, dimension: width)), width)
    }

    func testProgressFollowsDirectionSetting() {
        XCTAssertEqual(SlideMath.progress(fingerTravel: -0.2, gain: 2, natural: true), -0.4, accuracy: 1e-9)
        XCTAssertEqual(SlideMath.progress(fingerTravel: -0.2, gain: 2, natural: false), 0.4, accuracy: 1e-9)
        XCTAssertEqual(SlideMath.progress(fingerTravel: -0.9, gain: 2, natural: true), -1)
    }
}
