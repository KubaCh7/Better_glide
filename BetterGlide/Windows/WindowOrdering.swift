import CoreGraphics

/// Computes the stable, spatial switching order. Pure logic, unit-tested.
///
/// Order:
/// 1. display, left to right (then top to bottom) by the display's global bounds,
/// 2. within a display, by the window's left edge; windows whose left edges are within
///    `columnTolerance` points of each other form one "column",
/// 3. within a column, by `rank`: the order in which windows were first seen, seeded from
///    the z-order (frontmost first) when BetterGlide starts.
///
/// Why not live z-order for ties: focusing a window changes the z-order, so two stacked
/// windows would keep swapping places and the order would no longer be predictable.
enum WindowOrdering {
    struct Item: Equatable {
        let id: CGWindowID
        let frame: CGRect
        let rank: Int
    }

    static let columnTolerance: CGFloat = 12

    /// Displays sorted left-to-right, then top-to-bottom.
    static func sortedDisplays(_ displays: [CGRect]) -> [CGRect] {
        displays.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    /// Index (into `sortedDisplays`) of the display that contains most of `frame`.
    static func displayIndex(for frame: CGRect, sortedDisplays displays: [CGRect]) -> Int {
        guard !displays.isEmpty else { return 0 }
        var best = 0
        var bestArea: CGFloat = -1
        for (i, display) in displays.enumerated() {
            let overlap = display.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                best = i
                bestArea = area
            }
        }
        if bestArea > 0 { return best }
        // Entirely off-screen: nearest display by center distance.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.indices.min { a, b in
            distance(center, displays[a]) < distance(center, displays[b])
        } ?? 0
    }

    static func sorted(_ items: [Item], displays: [CGRect]) -> [CGWindowID] {
        let screens = sortedDisplays(displays)
        let byDisplay = Dictionary(grouping: items) { displayIndex(for: $0.frame, sortedDisplays: screens) }
        var result: [CGWindowID] = []
        result.reserveCapacity(items.count)
        for displayIndex in byDisplay.keys.sorted() {
            // Greedy columns over windows sorted by left edge. Unlike a tolerance-based
            // comparator this is transitive, so the result is deterministic.
            let windows = byDisplay[displayIndex]!.sorted { ($0.frame.minX, $0.rank) < ($1.frame.minX, $1.rank) }
            var column: [Item] = []
            var columnStart: CGFloat = 0
            func flush() {
                result += column.sorted { $0.rank < $1.rank }.map(\.id)
                column.removeAll()
            }
            for window in windows {
                if !column.isEmpty, window.frame.minX - columnStart > columnTolerance { flush() }
                if column.isEmpty { columnStart = window.frame.minX }
                column.append(window)
            }
            flush()
        }
        return result
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}

/// Next index when stepping through the spatial order.
enum WindowStep {
    case next, previous

    /// - Parameters:
    ///   - current: index of the focused window in the order, if it is in the list.
    ///   - wrap: whether stepping past an end jumps to the other end.
    /// - Returns: target index, or nil when already at an edge (and not wrapping).
    func target(from current: Int?, count: Int, wrap: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return self == .next ? 0 : count - 1 }
        let candidate = current + (self == .next ? 1 : -1)
        if (0..<count).contains(candidate) { return candidate }
        guard wrap, count > 1 else { return nil }
        return self == .next ? 0 : count - 1
    }
}
