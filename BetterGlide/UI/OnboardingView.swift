import SwiftUI

/// First-run guide: permissions, gesture conflict check and a live gesture test.
/// Permission state is polled once per second only while this window is open.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var feed: GestureFeed
    var gesturesAvailable: Bool
    var onDone: () -> Void

    @State private var accessibility = Permissions.accessibilityGranted
    @State private var inputMonitoring = Permissions.inputMonitoringGranted
    @State private var screenRecording = Permissions.screenRecordingGranted
    @State private var trackpad = TrackpadPreferences.read()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Witaj w BetterGlide").font(.largeTitle.bold())
                Text("Przełączaj zwykłe okna gestem, w stałej kolejności od lewej do prawej — jak pulpity.")
                    .foregroundStyle(.secondary)
            }

            Step(number: 1, title: "Dostępność (wymagane)", done: accessibility,
                 text: "Pozwala BetterGlide odczytać listę okien, podnieść wybrane okno i przywracać ich pozycje.") {
                Button("Nadaj dostęp…") { Permissions.requestAccessibility() }
            }

            Step(number: 2, title: "Nagrywanie ekranu (do animacji)", done: screenRecording,
                 text: "Pozwala zrobić zrzut ekranu na czas gestu, żeby ekran przesuwał się pod palcami jak przy pulpitach. Nic nie jest zapisywane. Po nadaniu uruchom BetterGlide ponownie.") {
                VStack(alignment: .trailing) {
                    Button("Nadaj dostęp…") { Permissions.requestScreenRecording() }
                    Button("Uruchom ponownie") { Permissions.relaunch() }
                }
            }

            Step(number: 3, title: "Monitorowanie wprowadzania (opcjonalne)", done: inputMonitoring,
                 text: "Zwykle niepotrzebne. Nadaj tylko, jeśli test gestu poniżej nic nie wykrywa.") {
                Button("Otwórz ustawienia…") { Permissions.requestInputMonitoring() }
            }

            Step(number: 4, title: "Gest gładzika", done: trackpad.conflict(for: settings.fingerCount) == nil,
                 text: "Wybierz liczbę palców. Systemowy gest o tej samej liczbie palców powinien być wyłączony lub przeniesiony.") {
                Picker("", selection: $settings.fingerCount) {
                    Text("3 palce").tag(3)
                    Text("4 palce").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            if let conflict = trackpad.conflict(for: settings.fingerCount) {
                ConflictNotice(conflict: conflict, fingerCount: settings.fingerCount)
                    .padding(.leading, 36)
            }

            if gesturesAvailable {
                GestureTestRow(feed: feed, fingerCount: settings.fingerCount)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            } else {
                Label("Prywatny framework MultitouchSupport jest niedostępny w tej wersji macOS — gesty nie zadziałają.",
                      systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(accessibility ? "Gotowe" : "Pomiń na razie") {
                    settings.hasCompletedOnboarding = true
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(poll) { _ in
            accessibility = Permissions.accessibilityGranted
            inputMonitoring = Permissions.inputMonitoringGranted
            screenRecording = Permissions.screenRecordingGranted
            trackpad = TrackpadPreferences.read()
        }
    }
}

private struct Step<Accessory: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
        }
    }
}
