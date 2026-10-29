import AppKit

/// Downloads a release DMG, copies the app out of it, re-signs it with this Mac's stable
/// signature (so permissions stay valid) and replaces the running app.
/// Files downloaded by URLSession are not quarantined, so Gatekeeper does not block them.
final class UpdateInstaller {
    enum InstallError: LocalizedError {
        case notWritable(String)
        case download(String)
        case mountFailed
        case appMissing
        case invalidApp(String)

        var errorDescription: String? {
            switch self {
            case .notWritable(let path):
                return "Brak uprawnień do zapisu w \(path)."
            case .download(let reason):
                return "Nie udało się pobrać aktualizacji: \(reason)"
            case .mountFailed:
                return "Nie udało się otworzyć pobranego pliku DMG."
            case .appMissing:
                return "Pobrany DMG nie zawiera BetterGlide.app."
            case .invalidApp(let reason):
                return "Pobrana aplikacja nie przeszła weryfikacji: \(reason)"
            }
        }
    }

    private var progressObservation: NSKeyValueObservation?

    /// `progress` and `failure` are called on the main thread. On success the app quits and
    /// the new version starts by itself.
    func install(_ release: ReleaseInfo, progress: @escaping (Double) -> Void,
                 failure: @escaping (Error) -> Void) {
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            failure(InstallError.notWritable(parent))
            return
        }

        let task = URLSession.shared.downloadTask(with: release.downloadURL) { location, response, error in
            do {
                if let error { throw InstallError.download(error.localizedDescription) }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw InstallError.download("serwer zwrócił błąd")
                }
                // The downloaded file is deleted when this handler returns: move it first.
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BetterGlideUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let dmg = work.appendingPathComponent("BetterGlide.dmg")
                try FileManager.default.moveItem(at: location, to: dmg)
                let staged = try Self.stage(dmg: dmg, in: work)
                DispatchQueue.main.async {
                    progress(1)
                    _ = AppReplacer.replaceAndRelaunch(with: staged, at: destination)
                }
            } catch {
                DispatchQueue.main.async { failure(error) }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { value, _ in
            let fraction = value.fractionCompleted
            DispatchQueue.main.async { progress(fraction) }
        }
        task.resume()
    }

    /// Mounts the DMG, copies the app out, verifies it and re-signs it for this Mac.
    private static func stage(dmg: URL, in work: URL) throws -> URL {
        let mountPoint = work.appendingPathComponent("mount", isDirectory: true)
        guard Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                             "-mountpoint", mountPoint.path]).succeeded else {
            throw InstallError.mountFailed
        }
        defer { Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"]) }

        let source = mountPoint.appendingPathComponent("BetterGlide.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw InstallError.appMissing }
        let staged = work.appendingPathComponent("BetterGlide.app")
        guard Shell.run("/usr/bin/ditto", [source.path, staged.path]).succeeded else {
            throw InstallError.invalidApp("kopiowanie nie powiodło się")
        }
        guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw InstallError.invalidApp("inny identyfikator aplikacji")
        }
        // Check the downloaded build's own signature before replacing it with ours.
        guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]).succeeded else {
            throw InstallError.invalidApp("nieprawidłowy podpis")
        }
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        do {
            try LocalSigner.shared.sign(staged)
        } catch {
            // Still install; permissions will just have to be granted again.
            UserDefaults.standard.set(true, forKey: SelfInstaller.resetPermissionsKey)
        }
        return staged
    }
}
