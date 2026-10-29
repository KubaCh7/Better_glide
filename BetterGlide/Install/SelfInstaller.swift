import AppKit
import os

/// Runs once at launch, before anything else, and makes sure BetterGlide
/// 1. lives in the Applications folder (not in Downloads or on the mounted DMG), and
/// 2. carries this Mac's stable signature (see `LocalSigner`),
/// fixing either by preparing a copy, swapping it in and relaunching — no Terminal needed.
enum SelfInstaller {
    private static let log = Logger(subsystem: "com.betterglide.BetterGlide", category: "install")
    private static let attemptKey = "selfInstallAttempt"
    /// Set when the signature changed: stale permission entries are cleared on next launch.
    static let resetPermissionsKey = "resetPermissionsOnNextLaunch"

    /// - Returns: true when a relaunch is under way and the app should not continue launching.
    static func prepareIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL.standardizedFileURL
        // Development builds from Xcode stay where they are.
        if current.path.contains("/Build/Products/") || current.path.contains("/DerivedData/") { return false }

        let target = installLocation(for: current)
        let needsMove = target.path != current.path
        let needsSigning = !LocalSigner.isLocallySigned(current)
        guard needsMove || needsSigning else { return false }

        // Never loop: one attempt per build and location.
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let marker = "\(build)|\(current.path)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: attemptKey) != marker else { return false }
        defaults.set(marker, forKey: attemptKey)

        do {
            let staged = try AppReplacer.stageCopy(of: current)
            try LocalSigner.shared.sign(staged)
            if needsSigning { defaults.set(true, forKey: resetPermissionsKey) }
            log.info("Installing to \(target.path) (move: \(needsMove), sign: \(needsSigning))")
            return AppReplacer.replaceAndRelaunch(with: staged, at: target)
        } catch {
            log.error("Self-install failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Clears permission entries that belong to an older signature of BetterGlide, so the
    /// system asks again instead of showing a switch that is "on" but does not apply.
    static func resetStalePermissionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: resetPermissionsKey) else { return }
        defaults.set(false, forKey: resetPermissionsKey)
        Permissions.resetEntries()
    }

    /// Where BetterGlide should live: where it already is if that is an Applications
    /// folder, otherwise /Applications (or ~/Applications without write access).
    private static func installLocation(for current: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parent = current.deletingLastPathComponent().path
        if parent == "/Applications" || parent == home + "/Applications" { return current }
        if FileManager.default.isWritableFile(atPath: "/Applications") {
            return URL(fileURLWithPath: "/Applications/BetterGlide.app")
        }
        let userApps = URL(fileURLWithPath: home + "/Applications", isDirectory: true)
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        return userApps.appendingPathComponent("BetterGlide.app")
    }
}
