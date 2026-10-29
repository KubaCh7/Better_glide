import XCTest

/// Runs the real tools (openssl, security, codesign): verifies on macOS that BetterGlide can
/// create its own signing identity and that re-signing keeps the same identity.
final class LocalSignerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        Shell.run("/usr/bin/security", ["delete-keychain", directory.appendingPathComponent("signing.keychain-db").path])
        try? FileManager.default.removeItem(at: directory)
    }

    private func copyOfSystemTool() throws -> URL {
        let binary = FileManager.default.temporaryDirectory.appendingPathComponent("tool-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        addTeardownBlock { try? FileManager.default.removeItem(at: binary) }
        return binary
    }

    func testSignsWithStableLocalIdentity() throws {
        let signer = LocalSigner(directory: directory)
        try signer.ensureIdentity()
        XCTAssertTrue(signer.hasIdentity)

        let binary = try copyOfSystemTool()
        try signer.sign(binary)
        XCTAssertEqual(LocalSigner.signer(of: binary), LocalSigner.identityName)
        XCTAssertTrue(LocalSigner.isLocallySigned(binary))

        // A second signature (e.g. the next update) uses the same certificate.
        let requirement1 = Shell.run("/usr/bin/codesign", ["-d", "-r-", binary.path]).output
        let second = try copyOfSystemTool()
        try signer.sign(second)
        let requirement2 = Shell.run("/usr/bin/codesign", ["-d", "-r-", second.path]).output
        XCTAssertTrue(requirement1.contains("certificate leaf"))
        XCTAssertEqual(requirement1.components(separatedBy: "certificate leaf").last,
                       requirement2.components(separatedBy: "certificate leaf").last)
    }

    func testAdHocSignatureIsNotLocal() throws {
        let binary = try copyOfSystemTool()
        XCTAssertTrue(Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", binary.path]).succeeded)
        XCTAssertNil(LocalSigner.signer(of: binary))
        XCTAssertFalse(LocalSigner.isLocallySigned(binary))
    }
}
