import AppKit

/// Downloads a release DMG, copies the app out of it and replaces the running app.
///
/// The swap happens in a tiny shell helper that waits until BetterGlide has quit, moves the
/// old bundle aside, copies the new one in its place (restoring the old one if that fails)
/// and relaunches it. Files downloaded by URLSession are not quarantined, so Gatekeeper
/// does not block the updated app.
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
                return "Brak uprawnień do zapisu w \(path). Przenieś BetterGlide do folderu Aplikacje i spróbuj ponownie."
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
        guard FileManager.default.isWritableFile(atPath: parent), !parent.hasPrefix("/Volumes/") else {
            failure(InstallError.notWritable(parent))
            return
        }

        let task = URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] location, response, error in
            self?.progressObservation = nil
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
                    Self.replaceAndRelaunch(with: staged, destination: destination)
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

    /// Mounts the DMG, copies the app next to it and checks it is a valid BetterGlide build.
    private static func stage(dmg: URL, in work: URL) throws -> URL {
        let mountPoint = work.appendingPathComponent("mount", isDirectory: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                       "-mountpoint", mountPoint.path]) == 0 else {
            throw InstallError.mountFailed
        }
        defer { run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"]) }

        let source = mountPoint.appendingPathComponent("BetterGlide.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw InstallError.appMissing }
        let staged = work.appendingPathComponent("BetterGlide.app")
        guard run("/usr/bin/ditto", [source.path, staged.path]) == 0 else {
            throw InstallError.invalidApp("kopiowanie nie powiodło się")
        }
        guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw InstallError.invalidApp("inny identyfikator aplikacji")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]) == 0 else {
            throw InstallError.invalidApp("nieprawidłowy podpis")
        }
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    private static func replaceAndRelaunch(with staged: URL, destination: URL) {
        // $1 = our PID, $2 = staged app, $3 = installed app
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$3.previous"
        if /bin/mv "$3" "$3.previous" && /usr/bin/ditto "$2" "$3"; then
          /bin/rm -rf "$3.previous"
        else
          /bin/rm -rf "$3"
          /bin/mv "$3.previous" "$3"
        fi
        /bin/rm -rf "$(/usr/bin/dirname "$2")"
        /usr/bin/open "$3"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                            staged.path, destination.path]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("BetterGlide: could not start the update helper: \(error)")
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
