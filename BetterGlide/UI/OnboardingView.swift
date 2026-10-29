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
        ZStack {
            GlassBackdrop()
            VStack(alignment: .leading, spacing: 14) {
                GlassHeader(title: "Witaj w BetterGlide",
                            subtitle: "Przełączaj zwykłe okna gestem — jak pulpity.")
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                Step(number: 1, title: "Dostępność (wymagane)", done: accessibility,
                     text: "Pozwala BetterGlide odczytać listę okien, podnieść wybrane okno i przywracać ich pozycje.") {
                    Button("Nadaj dostęp…") { Permissions.requestAccessibility() }
                        .glassButton(prominent: !accessibility)
                }

                Step(number: 2, title: "Nagrywanie ekranu (do animacji)", done: screenRecording,
                     text: "Zrzut ekranu na czas gestu, żeby ekran przesuwał się pod palcami jak przy pulpitach. Nic nie jest zapisywane. Po nadaniu uruchom BetterGlide ponownie.") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Nadaj dostęp…") { Permissions.requestScreenRecording() }
                            .glassButton(prominent: !screenRecording)
                        Button("Uruchom ponownie") { Permissions.relaunch() }
                            .glassButton()
                    }
                }

                Step(number: 3, title: "Monitorowanie wprowadzania (opcjonalne)", done: inputMonitoring,
                     text: "Zwykle niepotrzebne. Nadaj tylko, jeśli test gestu poniżej nic nie wykrywa.") {
                    Button("Otwórz…") { Permissions.requestInputMonitoring() }
                        .glassButton()
                }

                Step(number: 4, title: "Gest gładzika", done: trackpad.conflict(for: settings.fingerCount) == nil,
                     text: "Systemowy gest o tej samej liczbie palców powinien być wyłączony lub przeniesiony.") {
                    Picker("", selection: $settings.fingerCount) {
                        Text("3 palce").tag(3)
                        Text("4 palce").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                } footer: {
                    if let conflict = trackpad.conflict(for: settings.fingerCount) {
                        ConflictNotice(conflict: conflict, fingerCount: settings.fingerCount)
                            .padding(.leading, 36)
                    }
                }

                Group {
                    if gesturesAvailable {
                        GestureTestRow(feed: feed, fingerCount: settings.fingerCount)
                    } else {
                        Label("Prywatny framework MultitouchSupport jest niedostępny w tej wersji macOS — gesty nie zadziałają.",
                              systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .glassPanel(cornerRadius: 16)

                HStack {
                    Spacer()
                    Button(accessibility ? "Gotowe" : "Pomiń na razie") {
                        settings.hasCompletedOnboarding = true
                        onDone()
                    }
                    .glassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .padding(.top, 16) // room for the transparent title bar
        }
        .frame(width: 600)
        .onReceive(poll) { _ in
            accessibility = Permissions.accessibilityGranted
            inputMonitoring = Permissions.inputMonitoringGranted
            screenRecording = Permissions.screenRecordingGranted
            trackpad = TrackpadPreferences.read()
        }
    }
}

private struct Step<Accessory: View, Footer: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let text: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            footer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }
}

extension Step where Footer == EmptyView {
    init(number: Int, title: String, done: Bool, text: String,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(number: number, title: title, done: done, text: text,
                  accessory: accessory, footer: { EmptyView() })
    }
}
