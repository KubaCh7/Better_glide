import Foundation

/// Minimal bindings to the private `MultitouchSupport.framework`.
///
/// PRIVATE API: MultitouchSupport is undocumented. We load it with `dlopen`/`dlsym`
/// instead of linking against it, so the app still launches (with gestures disabled)
/// if Apple ever removes or renames a symbol. These are the same entry points used by
/// long-lived open-source tools (MiddleClick, OpenMultitouchSupport, Fingerpaint).
///
/// The callback receives raw trackpad contacts *before* the system gesture recognizer,
/// so it works for any finger count, but it cannot consume or block the system gesture.
enum MultitouchBridge {
    /// One finger contact, normalized to the trackpad surface:
    /// x: 0 (left) ... 1 (right), y: 0 (bottom) ... 1 (top).
    struct Contact: Equatable {
        let identifier: Int32
        let state: Int32
        let x: Float
        let y: Float

        /// MTTouchState: 4 = make touch, 5 = touching. Other states are hover,
        /// lift-off or "lingering" contacts that should not count as fingers.
        var isTouching: Bool { state == 4 || state == 5 }
    }

    typealias FrameHandler = (_ contacts: [Contact], _ timestamp: Double) -> Void

    /// Called on MultitouchSupport's private thread for every contact frame
    /// (only while fingers are on the trackpad, plus one empty frame on lift-off).
    /// A C callback cannot capture context, hence the static.
    static var frameHandler: FrameHandler?

    private(set) static var isRunning = false
    private static var devices: [UnsafeMutableRawPointer] = []
    /// Holding the list keeps the device objects alive while callbacks are registered.
    private static var deviceList: CFMutableArray?

    // MARK: - Private symbol types

    // int (*MTContactCallbackFunction)(MTDeviceRef, MTTouch *, int count, double timestamp, int frame)
    private typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private struct Symbols {
        let createList: CreateListFn
        let register: RegisterFn
        let unregister: RegisterFn
        let start: StartFn
        let stop: StopFn
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private static let symbols: Symbols? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        guard
            let createList = load("MTDeviceCreateList", as: CreateListFn.self),
            let register = load("MTRegisterContactFrameCallback", as: RegisterFn.self),
            let unregister = load("MTUnregisterContactFrameCallback", as: RegisterFn.self),
            let start = load("MTDeviceStart", as: StartFn.self),
            let stop = load("MTDeviceStop", as: StopFn.self)
        else { return nil }
        return Symbols(createList: createList, register: register, unregister: unregister,
                       start: start, stop: stop)
    }()

    /// `true` if the private framework and all required symbols were found.
    static var isAvailable: Bool { symbols != nil }

    // MTTouch layout (96 bytes per contact, stable since 10.x). We read individual fields
    // by byte offset instead of mirroring the struct, so Swift layout rules cannot bite us:
    //   0 frame:Int32, 8 timestamp:Double, 16 identifier:Int32, 20 state:Int32,
    //   24 fingerID:Int32, 28 handID:Int32, 32 normalized.pos.x:Float, 36 normalized.pos.y:Float, ...
    private static let touchStride = 96

    private static let callback: ContactCallback = { _, data, count, timestamp, _ in
        guard let handler = MultitouchBridge.frameHandler else { return 0 }
        var contacts: [Contact] = []
        if let data, count > 0 {
            contacts.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let base = data + i * MultitouchBridge.touchStride
                contacts.append(Contact(
                    identifier: base.load(fromByteOffset: 16, as: Int32.self),
                    state: base.load(fromByteOffset: 20, as: Int32.self),
                    x: base.load(fromByteOffset: 32, as: Float.self),
                    y: base.load(fromByteOffset: 36, as: Float.self)
                ))
            }
        }
        handler(contacts, timestamp)
        return 0
    }

    /// Registers the callback on every multitouch device (built-in trackpad,
    /// Magic Trackpad, Magic Mouse). Returns the number of devices started.
    @discardableResult
    static func start() -> Int {
        guard let symbols else { return 0 }
        stop()
        guard let list = symbols.createList()?.takeRetainedValue() else { return 0 }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            symbols.register(device, callback)
            symbols.start(device, 0)
            devices.append(device)
        }
        deviceList = list
        isRunning = !devices.isEmpty
        return devices.count
    }

    static func stop() {
        guard let symbols else { return }
        for device in devices {
            symbols.unregister(device, callback)
            symbols.stop(device)
        }
        devices.removeAll()
        deviceList = nil
        isRunning = false
    }
}
