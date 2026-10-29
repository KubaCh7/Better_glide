import AppKit

/// Puts a prepared copy of BetterGlide in place of the installed one and starts it.
///
/// A tiny shell helper waits until this process has quit, moves the old bundle aside,
/// copies the new one in (restoring the old bundle if that fails) and relaunches.
enum AppReplacer {
    static func replaceAndRelaunch(with staged: URL, at destination: URL) -> Bool {
        // $1 = our PID, $2 = staged app, $3 = destination
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$3.previous"
        if [ -e "$3" ]; then /bin/mv "$3" "$3.previous"; fi
        if /usr/bin/ditto "$2" "$3"; then
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
        } catch {
            NSLog("BetterGlide: could not start the install helper: \(error)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    /// Copies `app` into a fresh temporary folder, without the quarantine flag.
    static func stageCopy(of app: URL) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterGlideInstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let staged = work.appendingPathComponent("BetterGlide.app")
        let copy = Shell.run("/usr/bin/ditto", [app.path, staged.path])
        guard copy.succeeded else { throw LocalSigner.SigningError.failed("kopiowanie: \(copy.output)") }
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }
}
