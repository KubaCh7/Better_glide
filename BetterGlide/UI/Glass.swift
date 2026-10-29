import SwiftUI

// Neutral (gray) Liquid Glass on macOS 26+, with a material fallback for macOS 14–15.
// Standard controls (Form, Toggle, Picker, menus, window chrome) adopt Liquid Glass
// automatically when built with the macOS 26 SDK; these helpers cover custom surfaces.

extension View {
    /// A floating, untinted glass panel.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                )
        }
    }

    /// Untinted glass button.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// App icon + title header used by the glass windows.
struct GlassHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
