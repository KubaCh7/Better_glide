import AppKit

/// Watches for monitors being connected, disconnected, rearranged or changing resolution.
///
/// - `onWillChange` fires on the first "begin configuration" callback, while windows are
///   still where the user left them (best moment for a final snapshot).
/// - `onSettled` fires once the setup has been stable for `settleDelay` (bursts of
///   callbacks are coalesced); `changed` tells whether the configuration key differs.
final class DisplayConfigObserver {
    var onWillChange: (() -> Void)?
    var onSettled: ((_ configuration: DisplayConfiguration, _ changed: Bool) -> Void)?

    private(set) var current = DisplayConfiguration.current()
    private let settleDelay: TimeInterval
    private var pending: DispatchWorkItem?
    private var changeInProgress = false
    private var screenObserver: NSObjectProtocol?

    init(settleDelay: TimeInterval = 1.5) {
        self.settleDelay = settleDelay
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(Self.callback, context)
        // Belt and braces: AppKit's notification also covers changes the CG callback
        // reports late (e.g. resolution changes from System Settings).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleSettle()
        }
    }

    func stop() {
        CGDisplayRemoveReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        pending?.cancel()
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard let context else { return }
        let observer = Unmanaged<DisplayConfigObserver>.fromOpaque(context).takeUnretainedValue()
        let isBegin = flags.contains(.beginConfigurationFlag)
        DispatchQueue.main.async {
            if isBegin {
                observer.beginChange()
            } else {
                observer.scheduleSettle()
            }
        }
    }

    private func beginChange() {
        guard !changeInProgress else { return }
        changeInProgress = true
        onWillChange?()
    }

    private func scheduleSettle() {
        changeInProgress = true
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settle() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    private func settle() {
        changeInProgress = false
        let new = DisplayConfiguration.current()
        let changed = new.key != current.key
        current = new
        onSettled?(new, changed)
    }
}
