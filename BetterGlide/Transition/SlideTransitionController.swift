import AppKit

/// Drives one swipe: the screen follows the fingers like switching Spaces, and lifting the
/// fingers either completes the switch (the next window is raised) or springs back.
///
/// Without the Screen Recording permission (or with the animation turned off) the same
/// commit rules apply, just without the slide.
final class SlideTransitionController {
    private let switcher: WindowSwitcher
    private let settings: AppSettings
    private let snapshotter = ScreenSnapshotter()
    private let overlay = SlideOverlay()

    /// Every finished swipe, for the live "test" fields in the UI.
    var onSwipe: ((SwipeDirection) -> Void)?

    private struct Session {
        let id: Int
        let neighbors: WindowSwitcher.Neighbors
        let homeDisplay: CGDirectDisplayID
        let animated: Bool
        var geometries: [CGDirectDisplayID: DisplayGeometry] = [:]
        var snapshots: ScreenSnapshotter.Result?
        var progress: CGFloat = 0
        /// Side the overlay is currently set up for (1 = right/next, -1 = left/previous).
        var configuredSide = 0
        /// Fingers lifted before the snapshots arrived.
        var pendingCommit: (target: TrackedWindow, fromRight: Bool, velocity: CGFloat)?
    }

    private var session: Session?
    private var lastSessionID = 0

    init(switcher: WindowSwitcher, settings: AppSettings) {
        self.switcher = switcher
        self.settings = settings
    }

    func handle(_ event: SwipeEvent) {
        switch event {
        case .armed:
            // A new gesture interrupts a slide that is still finishing.
            overlay.finishImmediately()
            session = nil
        case .began:
            begin()
        case .changed(let dx):
            guard session != nil else { return }
            session?.progress = progress(for: dx)
            render()
        case .ended(let dx, let velocity):
            // Reported even without permissions, so the onboarding test works from the start.
            if abs(dx) > 0.02 { onSwipe?(dx < 0 ? .left : .right) }
            end(dx: dx, velocity: velocity)
        case .cancelled:
            guard session != nil else { return }
            if overlay.isVisible { overlay.cancel() }
            session = nil
        }
    }

    // MARK: - Gesture phases

    private func begin() {
        guard settings.isEnabled, AX.isTrusted else { return }
        let neighbors = switcher.neighbors()
        let home = neighbors.current.flatMap { DisplayGeometry.displayID(containing: $0.frame) } ?? CGMainDisplayID()
        lastSessionID += 1
        let animated = settings.slideAnimation && ScreenSnapshotter.isPermitted
        var session = Session(id: lastSessionID, neighbors: neighbors, homeDisplay: home, animated: animated)
        guard animated else {
            self.session = session
            return
        }

        // Capture only what this swipe can show: the involved displays and the two neighbours.
        let targets = [neighbors.previous, neighbors.next].compactMap { $0 }
        var displays = [home]
        for window in targets {
            if let id = DisplayGeometry.displayID(containing: window.frame), !displays.contains(id) {
                displays.append(id)
            }
        }
        for id in displays {
            session.geometries[id] = DisplayGeometry(displayID: id)
        }
        var windows: [(id: CGWindowID, size: CGSize, scale: CGFloat)] = []
        for window in targets where !windows.contains(where: { $0.id == window.id }) {
            let display = DisplayGeometry.displayID(containing: window.frame) ?? home
            windows.append((window.id, window.frame.size, session.geometries[display]?.scale ?? 2))
        }
        self.session = session

        let id = session.id
        let request = ScreenSnapshotter.Request(displays: Array(session.geometries.values), windows: windows)
        snapshotter.capture(request) { [weak self] result in
            guard let self, self.session?.id == id else { return }
            self.session?.snapshots = result
            if let pending = self.session?.pendingCommit {
                self.render()
                self.commit(to: pending.target, fromRight: pending.fromRight, velocity: pending.velocity)
            } else {
                self.render()
            }
        }
    }

    private func end(dx: Float, velocity rawVelocity: Float) {
        guard let current = session else { return }

        let progress = self.progress(for: dx)
        let velocity = CGFloat(rawVelocity) * settings.slideGain * (settings.direction == .natural ? 1 : -1)
        session?.progress = progress
        let fromRight = progress < 0
        let target = fromRight ? current.neighbors.next : current.neighbors.previous

        guard let target, SlideMath.shouldCommit(progress: progress, velocity: velocity) else {
            if target == nil, abs(progress) > 0.05 {
                // Edge of the list: same "bump" feel as the last Space.
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            if overlay.isVisible { overlay.cancel(velocity: velocity) }
            session = nil
            return
        }

        if current.animated, current.snapshots == nil {
            // Quick flick: wait briefly for the snapshots so the slide can still play.
            session?.pendingCommit = (target, fromRight, velocity)
            let id = current.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.session?.id == id, let pending = self.session?.pendingCommit else { return }
                self.session = nil
                self.switcher.focus(pending.target)
            }
            return
        }
        commit(to: target, fromRight: fromRight, velocity: velocity)
    }

    private func commit(to target: TrackedWindow, fromRight: Bool, velocity: CGFloat) {
        // Raise the real window now; it is ready underneath when the overlay fades out.
        switcher.focus(target)
        if overlay.isVisible {
            overlay.complete(fromRight: fromRight, velocity: velocity)
        }
        session = nil
    }

    // MARK: - Rendering

    private func progress(for dx: Float) -> CGFloat {
        SlideMath.progress(fingerTravel: CGFloat(dx), gain: settings.slideGain,
                           natural: settings.direction == .natural)
    }

    private func render() {
        guard let current = session, let snapshots = current.snapshots else { return }
        let side = current.progress < 0 ? 1 : -1
        let target = side == 1 ? current.neighbors.next : current.neighbors.previous
        let displayID = target.flatMap { DisplayGeometry.displayID(containing: $0.frame) } ?? current.homeDisplay
        guard let geometry = current.geometries[displayID], let base = snapshots.displays[displayID] else { return }

        if current.configuredSide != side || !overlay.isVisible {
            let incoming = target.map { (base: base, window: snapshots.windows[$0.id], frame: $0.frame) }
            overlay.configure(geometry: geometry, current: base, incoming: incoming, fromRight: side == 1)
            session?.configuredSide = side
        }

        let width = geometry.visibleFrame.width
        let offset = target == nil
            ? SlideMath.rubberBand(current.progress * width, dimension: width)
            : current.progress * (width + SlideOverlay.gap)
        overlay.setOffset(offset)
    }
}
