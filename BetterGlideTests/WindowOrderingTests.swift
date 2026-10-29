import XCTest

final class WindowOrderingTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let externalLeft = CGRect(x: -2560, y: -400, width: 2560, height: 1440)

    private func item(_ id: CGWindowID, x: CGFloat, y: CGFloat = 50, w: CGFloat = 500, rank: Int) -> WindowOrdering.Item {
        WindowOrdering.Item(id: id, frame: CGRect(x: x, y: y, width: w, height: 400), rank: rank)
    }

    func testLeftToRightOnOneDisplay() {
        let items = [item(3, x: 1000, rank: 0), item(1, x: 0, rank: 1), item(2, x: 500, rank: 2)]
        XCTAssertEqual(WindowOrdering.sorted(items, displays: [laptop]), [1, 2, 3])
    }

    func testSameColumnUsesRankNotLiveZOrder() {
        // Two windows at (almost) the same x: rank decides, regardless of input order.
        let items = [item(7, x: 105, rank: 5), item(8, x: 100, rank: 2), item(9, x: 800, rank: 0)]
        XCTAssertEqual(WindowOrdering.sorted(items, displays: [laptop]), [8, 7, 9])
    }

    func testLeftDisplayComesFirst() {
        let items = [
            item(1, x: 10, rank: 0),                 // laptop
            item(2, x: -2000, y: 0, rank: 1),        // external, on the left
            item(3, x: -1000, y: 0, rank: 2),        // external
        ]
        XCTAssertEqual(WindowOrdering.sorted(items, displays: [laptop, externalLeft]), [2, 3, 1])
    }

    func testWindowAssignedToDisplayWithLargestOverlap() {
        let screens = WindowOrdering.sortedDisplays([laptop, externalLeft])
        let straddling = CGRect(x: -100, y: 0, width: 600, height: 400) // mostly on laptop
        XCTAssertEqual(WindowOrdering.displayIndex(for: straddling, sortedDisplays: screens), 1)
    }

    func testStepping() {
        XCTAssertEqual(WindowStep.next.target(from: 0, count: 3, wrap: false), 1)
        XCTAssertNil(WindowStep.next.target(from: 2, count: 3, wrap: false))
        XCTAssertEqual(WindowStep.next.target(from: 2, count: 3, wrap: true), 0)
        XCTAssertNil(WindowStep.previous.target(from: 0, count: 3, wrap: false))
        XCTAssertEqual(WindowStep.previous.target(from: 0, count: 3, wrap: true), 2)
        XCTAssertEqual(WindowStep.next.target(from: nil, count: 3, wrap: false), 0)
        XCTAssertEqual(WindowStep.previous.target(from: nil, count: 3, wrap: false), 2)
        XCTAssertNil(WindowStep.next.target(from: 0, count: 0, wrap: true))
    }
}
