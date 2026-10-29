import AppKit
import QuartzCore

/// Full-screen (minus menu bar and Dock) layer stage that slides "pages" like Spaces.
///
/// Page = a snapshot of the screen. The incoming page is the same snapshot with the target
/// window drawn on top, which is exactly what the screen looks like once it is raised.
/// Click-through, never activates, and is only on screen during a swipe.
final class SlideOverlay {
    /// Dark gap between pages, like between Spaces.
    static let gap: CGFloat = 40

    private var panel: NSPanel?
    private let root = CALayer()
    private let strip = CALayer()        // moves; holds both pages
    private let currentPage = CALayer()
    private let incomingPage = CALayer()
    private let incomingWindow = CALayer()
    private var geometry: DisplayGeometry?
    /// Bumped when a slide is abandoned, so its late callbacks do nothing.
    private var generation = 0

    private(set) var isVisible = false
    var pageWidth: CGFloat { geometry?.visibleFrame.width ?? 0 }

    init() {
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        strip.anchorPoint = .zero
        for page in [currentPage, incomingPage] {
            page.contentsGravity = .resize
            page.masksToBounds = true
            page.shadowColor = NSColor.black.cgColor
            page.shadowOpacity = 0.5
            page.shadowRadius = 18
            page.shadowOffset = .zero
            strip.addSublayer(page)
        }
        incomingWindow.contentsGravity = .resize
        incomingWindow.shadowColor = NSColor.black.cgColor
        incomingWindow.shadowOpacity = 0.45
        incomingWindow.shadowRadius = 22
        incomingWindow.shadowOffset = CGSize(width: 0, height: -10)
        incomingPage.addSublayer(incomingWindow)
        root.addSublayer(strip)
    }

    /// Sets up the pages. `incoming` nil = nothing to switch to (rubber band at the edge).
    func configure(geometry: DisplayGeometry, current: CGImage,
                   incoming: (base: CGImage, window: CGImage?, frame: CGRect)?, fromRight: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if self.geometry != geometry {
            panel.setFrame(geometry.visibleFrame, display: false)
        }
        self.geometry = geometry

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = geometry.visibleFrame.size
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = geometry.scale
        currentPage.frame = CGRect(origin: .zero, size: size)
        currentPage.contents = current
        currentPage.shadowPath = CGPath(rect: currentPage.bounds, transform: nil)

        if let incoming {
            let x = fromRight ? size.width + Self.gap : -(size.width + Self.gap)
            incomingPage.frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
            incomingPage.contents = incoming.base
            incomingPage.shadowPath = CGPath(rect: incomingPage.bounds, transform: nil)
            incomingWindow.contents = incoming.window
            incomingWindow.isHidden = incoming.window == nil
            incomingWindow.frame = geometry.layerRect(for: incoming.frame)
            incomingWindow.shadowPath = CGPath(roundedRect: incomingWindow.bounds, cornerWidth: 12,
                                               cornerHeight: 12, transform: nil)
            incomingPage.isHidden = false
        } else {
            incomingPage.isHidden = true
        }
        CATransaction.commit()

        if !isVisible {
            setOffset(0)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            isVisible = true
        }
    }

    /// Moves the pages by `x` points (negative = left), following the fingers.
    func setOffset(_ x: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.removeAllAnimations()
        strip.position = CGPoint(x: x, y: 0)
        CATransaction.commit()
    }

    /// Finishes the slide to the incoming page, then fades the overlay out to reveal the
    /// real screen (where the window has been raised in the meantime).
    func complete(fromRight: Bool, velocity: CGFloat) {
        let target = fromRight ? -(pageWidth + Self.gap) : pageWidth + Self.gap
        let generation = self.generation
        animate(to: target, velocity: velocity) { [weak self] in
            // Give the window server a moment to show the raised window, then cross-fade.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let self, self.generation == generation, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.15
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.hide()
                })
            }
        }
    }

    /// Springs back to the current page and hides.
    func cancel(velocity: CGFloat = 0) {
        let generation = self.generation
        animate(to: 0, velocity: velocity) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.hide()
        }
    }

    /// Ends any running animation at once (a new swipe started).
    func finishImmediately() {
        guard isVisible else { return }
        generation += 1
        strip.removeAllAnimations()
        hide()
    }

    private func animate(to x: CGFloat, velocity: CGFloat, completion: @escaping () -> Void) {
        let from = strip.presentation()?.position.x ?? strip.position.x
        let distance = abs(x - from)
        // Faster flick → shorter finish, within the range the system uses for Spaces.
        let speed = max(abs(velocity) * pageWidth, 1)
        let duration = min(max(Double(distance / speed), 0.18), 0.35)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = from
        animation.toValue = x
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.3, 1)
        strip.position = CGPoint(x: x, y: 0)
        strip.add(animation, forKey: "slide")
        CATransaction.commit()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        isVisible = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentPage.contents = nil
        incomingPage.contents = nil
        incomingWindow.contents = nil
        CATransaction.commit()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above normal and floating windows; the menu bar and Dock are outside its frame.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let view = NSView()
        view.layer = root
        view.wantsLayer = true // layer-hosting view: we own the layer tree
        panel.contentView = view
        return panel
    }
}
