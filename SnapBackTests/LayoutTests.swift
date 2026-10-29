import XCTest

final class LayoutTests: XCTestCase {
    private func saved(_ bundle: String, _ title: String, _ index: Int, x: CGFloat) -> SavedWindow {
        SavedWindow(bundleID: bundle, title: title, indexInApp: index, frame: CGRect(x: x, y: 0, width: 100, height: 100))
    }

    func testMatchesByTitleThenIndexThenRemaining() {
        let savedWindows = [
            saved("com.a", "Doc 1", 0, x: 10),
            saved("com.a", "Doc 2", 1, x: 20),
            saved("com.b", "Old title", 0, x: 30),
            saved("com.c", "X", 5, x: 40),
        ]
        let live = [
            LayoutMatcher.LiveWindow(id: 1, bundleID: "com.a", title: "Doc 2", indexInApp: 0),
            LayoutMatcher.LiveWindow(id: 2, bundleID: "com.a", title: "Doc 1", indexInApp: 1),
            LayoutMatcher.LiveWindow(id: 3, bundleID: "com.b", title: "New title", indexInApp: 0),
            LayoutMatcher.LiveWindow(id: 4, bundleID: "com.c", title: "Y", indexInApp: 0),
            LayoutMatcher.LiveWindow(id: 5, bundleID: "com.d", title: "Z", indexInApp: 0),
        ]
        let result = LayoutMatcher.match(live: live, saved: savedWindows)
        XCTAssertEqual(result[1]?.minX, 20) // title
        XCTAssertEqual(result[2]?.minX, 10) // title
        XCTAssertEqual(result[3]?.minX, 30) // index
        XCTAssertEqual(result[4]?.minX, 40) // leftover entry of the same app
        XCTAssertNil(result[5])             // unknown app
    }

    func testSavedEntryUsedOnce() {
        let result = LayoutMatcher.match(
            live: [
                LayoutMatcher.LiveWindow(id: 1, bundleID: "com.a", title: "Same", indexInApp: 0),
                LayoutMatcher.LiveWindow(id: 2, bundleID: "com.a", title: "Same", indexInApp: 1),
            ],
            saved: [saved("com.a", "Same", 0, x: 10)]
        )
        XCTAssertEqual(result.count, 1)
    }

    func testStoreMergeKeepsAppsThatAreNotRunning() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("layouts.json")
        let store = LayoutStore(fileURL: url)
        store.merge([saved("com.a", "A", 0, x: 1), saved("com.b", "B", 0, x: 2)], summary: "s", for: "k")
        store.merge([saved("com.a", "A", 0, x: 99)], summary: "s", for: "k")

        let reloaded = LayoutStore(fileURL: url)
        let windows = try XCTUnwrap(reloaded.layout(for: "k")?.windows)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.first { $0.bundleID == "com.a" }?.frame.minX, 99)
        XCTAssertEqual(windows.first { $0.bundleID == "com.b" }?.frame.minX, 2)
    }

    func testConfigurationKeyIsOrderIndependent() {
        let a = DisplayConfiguration.Display(vendor: 1, model: 2, serial: 3, pixelWidth: 3024, pixelHeight: 1964,
                                             bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltin: true)
        let b = DisplayConfiguration.Display(vendor: 4, model: 5, serial: 6, pixelWidth: 2560, pixelHeight: 1440,
                                             bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440), isBuiltin: false)
        XCTAssertEqual(DisplayConfiguration(displays: [a, b]).key, DisplayConfiguration(displays: [b, a]).key)

        var moved = b
        moved.bounds.origin.x = -2560 // same monitor, now arranged on the left
        XCTAssertNotEqual(DisplayConfiguration(displays: [a, b]).key, DisplayConfiguration(displays: [a, moved]).key)
    }
}
