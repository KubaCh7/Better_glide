import Foundation

// SwipeProbe: minimal command-line prototype that verifies the MultitouchSupport approach
// on the current macOS version. It logs finger-count changes and recognized swipes.
//
// Usage: SwipeProbe [fingerCount]   (default 3; Ctrl+C to quit)
//        SwipeProbe --check          (only verify the private framework loads, then exit)

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments.dropFirst()
let checkOnly = arguments.contains("--check")
let fingerCount = arguments.compactMap(Int.init).first ?? 3
let detector = SwipeDetector(configuration: SwipeConfiguration(fingerCount: fingerCount))
var lastTouchingCount = -1

print("SwipeProbe: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
guard MultitouchBridge.isAvailable else {
    print("ERROR: MultitouchSupport.framework or its symbols are not available on this system.")
    exit(1)
}

// Runs on MultitouchSupport's thread; printing from here is fine for a probe.
MultitouchBridge.frameHandler = { contacts, timestamp in
    let touching = contacts.filter(\.isTouching)
    if touching.count != lastTouchingCount {
        lastTouchingCount = touching.count
        let states = contacts.map { String($0.state) }.joined(separator: ",")
        let positions = touching
            .map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }
            .joined(separator: " ")
        print(String(format: "[%.3f] fingers: %d  states: [%@]  %@",
                     timestamp, touching.count, states, positions))
    }
    let points = touching.map { SwipeDetector.Point(x: $0.x, y: $0.y) }
    if let direction = detector.process(touching: points, timestamp: timestamp) {
        print(String(format: "[%.3f] >>> SWIPE %@ (%d fingers)",
                     timestamp, direction.rawValue.uppercased(), fingerCount))
    }
}

let devices = MultitouchBridge.start()
if checkOnly {
    print("OK: MultitouchSupport symbols resolved; \(devices) multitouch device(s) found.")
    MultitouchBridge.stop()
    exit(0)
}
print("Listening on \(devices) multitouch device(s) for \(fingerCount)-finger swipes. Ctrl+C to quit.")
if devices == 0 {
    print("WARNING: no multitouch devices found (no trackpad connected?).")
}

signal(SIGINT) { _ in
    MultitouchBridge.stop()
    print("\nStopped.")
    exit(0)
}

RunLoop.main.run()
