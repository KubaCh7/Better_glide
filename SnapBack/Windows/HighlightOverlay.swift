import AppKit
import QuartzCore

/// Briefly draws a rounded accent border around the window that just received focus,
/// with a small slide in the swipe direction. Click-through and never activates.
final class HighlightOverlay {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// - Parameters:
    ///   - frame: window frame in global top-left coordinates (CG/AX space).
    ///   - slideFrom: horizontal offset the border slides in from (0 = no slide).
    func flash(frame: CGRect, slideFrom offset: CGFloat = 0) {
        let cocoaFrame = Self.cocoaRect(fromTopLeft: frame).insetBy(dx: -3, dy: -3)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        hideWork?.cancel()

        let start = cocoaFrame.offsetBy(dx: offset, dy: 0)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(cocoaFrame, display: true)
        }

        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.borderWidth = 4
        view.layer?.cornerRadius = 12
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
        panel.contentView = view
        return panel
    }

    /// CG/AX global coordinates have their origin at the top-left of the primary display
    /// and grow downwards; Cocoa's origin is the bottom-left of the primary display.
    static func cocoaRect(fromTopLeft rect: CGRect) -> CGRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
