import AppKit

/// Reads the system trackpad gesture settings to detect conflicts with BetterGlide's swipe.
///
/// UNDOCUMENTED: these preference keys are what System Settings → Trackpad → More Gestures
/// writes. They have been stable for many macOS releases but are not public API.
struct TrackpadPreferences {
    /// 0 = off, 1 = "Swipe between pages" with 3 fingers, 2 = "Swipe between full-screen apps".
    var threeFingerHorizontal: Int
    /// 0 = off, 2 = "Swipe between full-screen apps" with 4 fingers.
    var fourFingerHorizontal: Int
    /// Accessibility → Pointer Control → "Three finger drag".
    var threeFingerDrag: Bool

    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",                  // built-in trackpad
        "com.apple.driver.AppleBluetoothMultitouch.trackpad", // Magic Trackpad
    ]

    static func read() -> TrackpadPreferences {
        // Missing keys mean "system default", which uses horizontal swipes for Spaces.
        TrackpadPreferences(
            threeFingerHorizontal: intValue("TrackpadThreeFingerHorizSwipeGesture") ?? 2,
            fourFingerHorizontal: intValue("TrackpadFourFingerHorizSwipeGesture") ?? 2,
            threeFingerDrag: (intValue("TrackpadThreeFingerDrag") ?? 0) != 0
        )
    }

    private static func intValue(_ key: String) -> Int? {
        for domain in domains {
            CFPreferencesAppSynchronize(domain as CFString)
            if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber {
                return value.intValue
            }
        }
        return nil
    }

    /// Finger count BetterGlide should default to on first launch.
    var recommendedFingerCount: Int {
        if conflict(for: 3) == nil { return 3 }
        if conflict(for: 4) == nil { return 4 }
        return 3
    }

    /// Human readable description of a conflicting system gesture, or nil if there is none.
    func conflict(for fingerCount: Int) -> String? {
        if fingerCount == 3 {
            if threeFingerDrag {
                return "Włączone jest „Przeciąganie trzema palcami” (Dostępność) — przesunięcie 3 palcami przeciąga okna."
            }
            switch threeFingerHorizontal {
            case 2: return "System używa przesunięcia 3 palcami w poziomie do przełączania pełnoekranowych aplikacji (Spaces)."
            case 1: return "System używa przesunięcia 3 palcami w poziomie do przechodzenia między stronami."
            default: return nil
            }
        }
        if fingerCount == 4, fourFingerHorizontal != 0 {
            return "System używa przesunięcia 4 palcami w poziomie do przełączania pełnoekranowych aplikacji (Spaces)."
        }
        return nil
    }

    /// Step-by-step fix shown in onboarding and settings.
    static func instructions(for fingerCount: Int) -> String {
        if fingerCount == 3 {
            return "Ustawienia systemowe → Gładzik → Więcej gestów → „Przesuwanie między aplikacjami pełnoekranowymi”: wybierz „Przesuń w lewo lub w prawo czterema palcami” (lub Wyłącz). Jeśli „Przesuwanie między stronami” używa trzech palców, zmień je na dwa palce."
        }
        return "Ustawienia systemowe → Gładzik → Więcej gestów → „Przesuwanie między aplikacjami pełnoekranowymi”: wybierz „Przesuń w lewo lub w prawo trzema palcami” (lub Wyłącz)."
    }

    static func openTrackpadSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Trackpad-Settings.extension", // macOS 13+
            "x-apple.systempreferences:com.apple.preference.trackpad",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
