import AppKit
import SwiftUI

/// Latest recognized swipe, for live feedback in Settings/Onboarding.
final class GestureFeed: ObservableObject {
    struct Event: Equatable {
        let direction: SwipeDirection
        let date: Date
    }
    @Published var last: Event?
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var feed: GestureFeed
    var savedConfigurationCount: () -> Int
    var clearLayouts: () -> Void

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var trackpad = TrackpadPreferences.read()
    @State private var layoutsCleared = false

    var body: some View {
        Form {
            Section("Gest") {
                Picker("Liczba palców", selection: $settings.fingerCount) {
                    Text("3 palce").tag(3)
                    Text("4 palce").tag(4)
                }
                .pickerStyle(.segmented)

                if let conflict = trackpad.conflict(for: settings.fingerCount) {
                    ConflictNotice(conflict: conflict, fingerCount: settings.fingerCount)
                }

                Picker("Kierunek", selection: $settings.direction) {
                    Text("Naturalny (jak Spaces): w lewo → okno po prawej").tag(AppSettings.Direction.natural)
                    Text("Odwrócony: w prawo → okno po prawej").tag(AppSettings.Direction.inverted)
                }

                LabeledContent("Czułość") {
                    HStack {
                        Text("Długi ruch").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $settings.sensitivity, in: 0...1)
                        Text("Krótki ruch").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle("Zawijaj (z ostatniego okna na pierwsze)", isOn: $settings.wrapAround)
                GestureTestRow(feed: feed, fingerCount: settings.fingerCount)
            }

            Section("Wygląd") {
                Toggle("Podświetl ramkę okna po przełączeniu (animacja)", isOn: $settings.showHighlight)
                Toggle("Pokaż pozycję okna w pasku menu (np. 2/3)", isOn: $settings.showPositionInMenuBar)
            }

            Section("Układ okien") {
                Toggle("Przywracaj układ po zmianie konfiguracji monitorów", isOn: $settings.autoRestoreLayout)
                HStack {
                    Text("Zapamiętane konfiguracje: \(layoutsCleared ? 0 : savedConfigurationCount())")
                    Spacer()
                    Button("Wyczyść") {
                        clearLayouts()
                        layoutsCleared = true
                    }
                }
            }

            Section("Wykluczone aplikacje") {
                ExcludedAppsEditor(settings: settings)
            }

            Section("Ogólne") {
                Toggle("Przełączanie gestem włączone", isOn: $settings.isEnabled)
                Toggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = LoginItem.needsApproval
                                ? "Zatwierdź SnapBack w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania."
                                : nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trackpad = TrackpadPreferences.read()
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

struct ConflictNotice: View {
    let conflict: String
    let fingerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(conflict, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Oba gesty zadziałają naraz. " + TrackpadPreferences.instructions(for: fingerCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Otwórz ustawienia Gładzika") { TrackpadPreferences.openTrackpadSettings() }
        }
    }
}

struct GestureTestRow: View {
    @ObservedObject var feed: GestureFeed
    let fingerCount: Int

    var body: some View {
        HStack {
            Text("Test: przesuń \(fingerCount) palcami w lewo lub w prawo")
            Spacer()
            if let event = feed.last, Date().timeIntervalSince(event.date) < 5 {
                Label(event.direction == .left ? "w lewo" : "w prawo",
                      systemImage: event.direction == .left ? "arrow.left" : "arrow.right")
                    .foregroundStyle(.green)
                    .id(event.date)
                    .transition(.opacity)
            } else {
                Text("czekam…").foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: feed.last)
    }
}

struct ExcludedAppsEditor: View {
    @ObservedObject var settings: AppSettings

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !settings.isExcluded($0.bundleIdentifier) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        if settings.excludedBundleIDs.isEmpty {
            Text("Brak — wszystkie aplikacje biorą udział w przełączaniu.").foregroundStyle(.secondary)
        }
        ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
            HStack {
                Text(Self.name(for: bundleID))
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    settings.setExcluded(bundleID, false)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
        Menu("Dodaj uruchomioną aplikację…") {
            ForEach(runningApps, id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                    if let id = app.bundleIdentifier { settings.setExcluded(id, true) }
                }
            }
        }
    }

    private static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
