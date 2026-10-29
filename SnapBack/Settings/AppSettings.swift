import Foundation

/// User preferences, persisted in UserDefaults. Observed by SwiftUI and by `AppDelegate`.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Direction: String, CaseIterable, Identifiable {
        /// Like Spaces: fingers move left → go to the window on the right.
        case natural
        /// Fingers move right → go to the window on the right.
        case inverted
        var id: String { rawValue }
    }

    /// Called after any change (on the main thread).
    var onChange: (() -> Void)?

    @Published var isEnabled: Bool { didSet { store(isEnabled, Keys.enabled) } }
    @Published var fingerCount: Int { didSet { store(fingerCount, Keys.fingerCount) } }
    @Published var direction: Direction { didSet { store(direction.rawValue, Keys.direction) } }
    /// 0 (needs a long swipe) ... 1 (very sensitive).
    @Published var sensitivity: Double { didSet { store(sensitivity, Keys.sensitivity) } }
    @Published var wrapAround: Bool { didSet { store(wrapAround, Keys.wrapAround) } }
    @Published var showHighlight: Bool { didSet { store(showHighlight, Keys.showHighlight) } }
    @Published var showPositionInMenuBar: Bool { didSet { store(showPositionInMenuBar, Keys.showPosition) } }
    @Published var autoRestoreLayout: Bool { didSet { store(autoRestoreLayout, Keys.autoRestore) } }
    @Published var excludedBundleIDs: [String] { didSet { store(excludedBundleIDs, Keys.excluded) } }
    @Published var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, Keys.onboarding) } }

    private enum Keys {
        static let enabled = "enabled"
        static let fingerCount = "fingerCount"
        static let direction = "direction"
        static let sensitivity = "sensitivity"
        static let wrapAround = "wrapAround"
        static let showHighlight = "showHighlight"
        static let showPosition = "showPositionInMenuBar"
        static let autoRestore = "autoRestoreLayout"
        static let excluded = "excludedBundleIDs"
        static let onboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.direction: Direction.natural.rawValue,
            Keys.sensitivity: 0.5,
            Keys.wrapAround: false,
            Keys.showHighlight: true,
            Keys.showPosition: true,
            Keys.autoRestore: true,
            Keys.excluded: [String](),
            Keys.onboarding: false,
        ])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        // First launch: prefer 3 fingers unless the system already uses 3-finger horizontal swipes.
        if defaults.object(forKey: Keys.fingerCount) == nil {
            let preferred = TrackpadPreferences.read().recommendedFingerCount
            defaults.set(preferred, forKey: Keys.fingerCount)
        }
        fingerCount = defaults.integer(forKey: Keys.fingerCount) == 4 ? 4 : 3
        direction = Direction(rawValue: defaults.string(forKey: Keys.direction) ?? "") ?? .natural
        sensitivity = defaults.double(forKey: Keys.sensitivity)
        wrapAround = defaults.bool(forKey: Keys.wrapAround)
        showHighlight = defaults.bool(forKey: Keys.showHighlight)
        showPositionInMenuBar = defaults.bool(forKey: Keys.showPosition)
        autoRestoreLayout = defaults.bool(forKey: Keys.autoRestore)
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excluded) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    var swipeConfiguration: SwipeConfiguration {
        // Sensitivity 0 → 22% of the trackpad width, 1 → 6%.
        let threshold = Float(0.22 - 0.16 * min(max(sensitivity, 0), 1))
        return SwipeConfiguration(fingerCount: fingerCount, threshold: threshold)
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded {
            if !excludedBundleIDs.contains(bundleID) { excludedBundleIDs.append(bundleID) }
        } else {
            excludedBundleIDs.removeAll { $0 == bundleID }
        }
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
