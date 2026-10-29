import Foundation

/// Checks GitHub Releases for a newer build and installs it on request.
/// Automatic checks: shortly after launch, then once a day (one small HTTPS request).
final class UpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case failed(String)
    }

    @Published private(set) var state = State.idle
    @Published private(set) var lastChecked: Date?

    /// Called when a check finds a build the user has not been told about yet.
    var onUpdateFound: ((ReleaseInfo) -> Void)?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0

    private let installer = UpdateInstaller()
    private var timer: Timer?
    private var announcedBuild: Int?

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = state { return release }
        return nil
    }

    func setAutomaticChecks(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard self?.timer != nil else { return }
            self?.check()
        }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        if case .downloading = state { return }
        state = .checking
        var request = URLRequest(url: ReleaseInfo.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = data.flatMap(ReleaseInfo.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastChecked = Date()
                if let error {
                    self.state = .failed("Brak połączenia: \(error.localizedDescription)")
                } else if status != 200 {
                    self.state = .failed("GitHub odpowiedział kodem \(status). Spróbuj później.")
                } else if let release, release.isNewer(than: self.currentBuild) {
                    self.state = .available(release)
                    if self.announcedBuild != release.build {
                        self.announcedBuild = release.build
                        self.onUpdateFound?(release)
                    }
                } else {
                    self.state = .upToDate
                }
            }
        }.resume()
    }

    func install(_ release: ReleaseInfo) {
        state = .downloading(0)
        installer.install(release, progress: { [weak self] fraction in
            self?.state = .downloading(fraction)
        }, failure: { [weak self] error in
            self?.state = .failed(error.localizedDescription)
        })
    }
}
