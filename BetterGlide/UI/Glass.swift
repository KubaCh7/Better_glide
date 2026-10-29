import SwiftUI

// Liquid Glass (macOS 26+) with a material fallback for macOS 14–15.
// Standard controls (Form, Toggle, Picker, menus, window chrome) adopt Liquid Glass
// automatically when built with the macOS 26 SDK; these helpers cover custom surfaces.

extension View {
    /// A floating glass panel.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18))
                )
        }
    }

    /// Glass button; `prominent` tints it with the accent color (primary action).
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// Soft, colorful backdrop for glass windows: glass needs something behind it to refract.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.36, blue: 0.95), Color(red: 0.45, green: 0.27, blue: 0.92),
                         Color(red: 0.08, green: 0.65, blue: 0.80)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -180, y: -160)
            Circle()
                .fill(Color(red: 0.95, green: 0.45, blue: 0.85).opacity(0.40))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: 220, y: 200)
        }
        .ignoresSafeArea()
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
