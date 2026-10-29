import SwiftUI

struct UpdateView: View {
    @ObservedObject var updates: UpdateController
    var onClose: () -> Void

    var body: some View {
        ZStack {
            GlassBackdrop()
            VStack(alignment: .leading, spacing: 18) {
                GlassHeader(title: "Aktualizacje",
                            subtitle: "Zainstalowana wersja \(updates.currentVersion) (build \(updates.currentBuild))")
                    .foregroundStyle(.white)

                status
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel()

                if let release = updates.availableRelease, !release.notes.isEmpty {
                    ScrollView {
                        Text(Self.markdown(release.notes))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(18)
                    .glassPanel()
                }

                HStack {
                    if let checked = updates.lastChecked {
                        Text("Sprawdzono \(checked.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Button("Zamknij", action: onClose)
                        .glassButton()
                    actionButton
                }
            }
            .padding(24)
        }
        .frame(width: 520)
        .onAppear {
            switch updates.state {
            case .idle, .upToDate, .failed: updates.check()
            default: break
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.state {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Sprawdzanie aktualizacji…")
            }
        case .upToDate:
            Label("Masz najnowszą wersję.", systemImage: "checkmark.seal.fill")
                .font(.headline)
        case .available(let release):
            VStack(alignment: .leading, spacing: 4) {
                Label("Dostępna nowa wersja: build \(release.build)", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                if let date = release.publishedAt {
                    Text("Opublikowano \(date.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Text("Po instalacji BetterGlide uruchomi się ponownie. Uprawnienia pozostaną, jeśli build jest podpisany stałym certyfikatem (patrz README).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 8) {
                Text(fraction < 1 ? "Pobieranie…" : "Instalowanie…").font(.headline)
                ProgressView(value: fraction)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updates.state {
        case .available(let release):
            Button("Zainstaluj i uruchom ponownie") { updates.install(release) }
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
        case .downloading:
            Button("Instalowanie…") {}
                .glassButton(prominent: true)
                .disabled(true)
        default:
            Button("Sprawdź ponownie") { updates.check() }
                .glassButton(prominent: true)
                .disabled(updates.state == .checking)
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
