import Foundation
import Security

/// Gives BetterGlide a stable code signature on this Mac.
///
/// macOS stores the Accessibility and Screen Recording permissions for a specific code
/// signature. Downloaded builds are ad-hoc signed, so each one looks like a different app
/// and the permissions would silently stop applying after every update (the switch in
/// System Settings stays on, but for the old build). Instead, BetterGlide creates its own
/// self-signed certificate once, in a private keychain under Application Support, and
/// re-signs every installed or updated copy with it. The signature then stays the same.
struct LocalSigner {
    enum SigningError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case .failed(let reason) = self { return "Podpisywanie nie powiodło się: \(reason)" }
            return nil
        }
    }

    static let identityName = "BetterGlide Local Signing"
    static let shared = LocalSigner(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BetterGlide/Signing", isDirectory: true))

    let directory: URL
    private var keychain: URL { directory.appendingPathComponent("signing.keychain-db") }
    private var passwordFile: URL { directory.appendingPathComponent("keychain-password") }

    // MARK: - Inspecting signatures

    /// Common name of the certificate `url` is signed with; nil for ad-hoc or unsigned code.
    static func signer(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    static func isLocallySigned(_ url: URL) -> Bool {
        signer(of: url) == identityName
    }

    // MARK: - Identity

    var hasIdentity: Bool {
        FileManager.default.fileExists(atPath: keychain.path) && FileManager.default.fileExists(atPath: passwordFile.path)
    }

    /// Creates the certificate and private keychain if they do not exist yet.
    func ensureIdentity() throws {
        if hasIdentity { return }
        let fm = FileManager.default
        // Start clean if a previous attempt left half of it behind.
        Shell.run("/usr/bin/security", ["delete-keychain", keychain.path])
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])

        let password = UUID().uuidString
        let config = directory.appendingPathComponent("cert.cnf")
        let key = directory.appendingPathComponent("key.pem")
        let certificate = directory.appendingPathComponent("cert.pem")
        let p12 = directory.appendingPathComponent("cert.p12")
        defer { [config, key, certificate, p12].forEach { try? fm.removeItem(at: $0) } }

        try """
        [req]
        distinguished_name = dn
        x509_extensions = ext
        prompt = no
        [dn]
        CN = \(Self.identityName)
        [ext]
        basicConstraints = critical,CA:false
        keyUsage = critical,digitalSignature
        extendedKeyUsage = critical,codeSigning
        """.write(to: config, atomically: true, encoding: .utf8)

        // /usr/bin/openssl is LibreSSL; its PKCS#12 files are what `security import` expects.
        try check(Shell.run("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "7300",
                                                 "-config", config.path, "-keyout", key.path, "-out", certificate.path]))
        try check(Shell.run("/usr/bin/openssl", ["pkcs12", "-export", "-inkey", key.path, "-in", certificate.path,
                                                 "-name", Self.identityName, "-out", p12.path,
                                                 "-passout", "pass:\(password)"]))
        try check(Shell.run("/usr/bin/security", ["create-keychain", "-p", password, keychain.path]))
        try check(Shell.run("/usr/bin/security", ["unlock-keychain", "-p", password, keychain.path]))
        try check(Shell.run("/usr/bin/security", ["import", p12.path, "-k", keychain.path, "-P", password,
                                                  "-T", "/usr/bin/codesign"]))
        // Lets codesign use the key without any keychain dialog.
        try check(Shell.run("/usr/bin/security", ["set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                                                  "-s", "-k", password, keychain.path]))
        try password.write(to: passwordFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordFile.path)
    }

    // MARK: - Signing

    func sign(_ app: URL) throws {
        try ensureIdentity()
        let password = try String(contentsOf: passwordFile, encoding: .utf8)
        try check(Shell.run("/usr/bin/security", ["unlock-keychain", "-p", password, keychain.path]))

        // codesign looks identities up through the search list: add our keychain briefly.
        let original = Shell.run("/usr/bin/security", ["list-keychains", "-d", "user"]).output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty && $0 != keychain.path }
        Shell.run("/usr/bin/security", ["list-keychains", "-d", "user", "-s", keychain.path] + original)
        defer { Shell.run("/usr/bin/security", ["list-keychains", "-d", "user", "-s"] + original) }

        let find = Shell.run("/usr/bin/security", ["find-certificate", "-c", Self.identityName, "-Z", keychain.path])
        guard let hash = find.output.split(separator: "\n")
            .first(where: { $0.contains("SHA-1 hash") })?
            .split(separator: " ").last.map(String.init)
        else { throw SigningError.failed("brak certyfikatu") }

        try check(Shell.run("/usr/bin/codesign", ["--force", "--deep", "--timestamp=none",
                                                  "--keychain", keychain.path, "--sign", hash, app.path]))
        try check(Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]))
    }

    private func check(_ result: Shell.Result) throws {
        guard result.succeeded else { throw SigningError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
