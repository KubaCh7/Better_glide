import XCTest

final class ReleaseInfoTests: XCTestCase {
    private let sample = """
    {
      "name": "BetterGlide (build 12)",
      "body": "Co nowego: animacja",
      "html_url": "https://github.com/KubaCh7/Better_glide/releases/tag/latest-build",
      "published_at": "2026-10-29T20:41:53Z",
      "assets": [
        {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
        {"name": "BetterGlide.dmg", "browser_download_url": "https://github.com/KubaCh7/Better_glide/releases/download/latest-build/BetterGlide.dmg"}
      ]
    }
    """

    func testParsesLatestRelease() throws {
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(sample.utf8)))
        XCTAssertEqual(release.build, 12)
        XCTAssertEqual(release.downloadURL.lastPathComponent, "BetterGlide.dmg")
        XCTAssertEqual(release.notes, "Co nowego: animacja")
        XCTAssertNotNil(release.publishedAt)
    }

    func testRejectsReleaseWithoutDMGOrBuild() {
        XCTAssertNil(ReleaseInfo.parse(Data(#"{"name": "BetterGlide (build 3)", "assets": []}"#.utf8)))
        XCTAssertNil(ReleaseInfo.parse(Data(#"{"name": "Something", "assets": [{"name": "a.dmg", "browser_download_url": "https://x/a.dmg"}]}"#.utf8)))
        XCTAssertNil(ReleaseInfo.parse(Data("not json".utf8)))
    }

    func testBuildNumberAndComparison() throws {
        XCTAssertEqual(ReleaseInfo.buildNumber(in: "BetterGlide (build 9)"), 9)
        XCTAssertNil(ReleaseInfo.buildNumber(in: "BetterGlide"))
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(sample.utf8)))
        XCTAssertTrue(release.isNewer(than: 11))
        XCTAssertFalse(release.isNewer(than: 12))
    }
}
