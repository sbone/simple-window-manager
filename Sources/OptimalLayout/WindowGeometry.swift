import Foundation

enum Layout: UInt32, CaseIterable {
    case one = 1, two, three, four

    var title: String { "Layout \(rawValue)" }
}

struct WindowGeometry {
    private var cycle: [Layout: Int] = [:]

    mutating func apply(_ layout: Layout, usable: CGRect, setFrame: (CGRect) throws -> Void) rethrows {
        var next = self
        let frame = next.targetFrame(for: layout, usable: usable)
        try setFrame(frame)
        self = next
    }

    mutating func targetFrame(for layout: Layout, usable: CGRect) -> CGRect {
        switch layout {
        case .one:
            return usable
        case .two:
            let right = cycle[.two, default: 0] % 2 == 1
            cycle[.two] = (cycle[.two, default: 0] + 1) % 2
            return CGRect(x: right ? usable.midX : usable.minX, y: usable.minY,
                          width: usable.width / 2, height: usable.height)
        case .three:
            return CGRect(x: usable.minX + usable.width / 4, y: usable.minY,
                          width: usable.width / 2, height: usable.height)
        case .four:
            let quadrant = cycle[.four, default: 0] % 4
            cycle[.four] = (quadrant + 1) % 4
            let column = quadrant == 1 || quadrant == 2 ? 1 : 0
            let row = quadrant >= 2 ? 0 : 1
            return CGRect(x: usable.minX + CGFloat(column) * usable.width / 2,
                          y: usable.minY + CGFloat(row) * usable.height / 2,
                          width: usable.width / 2, height: usable.height / 2)
        }
    }

    static func movedFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let x = (frame.minX - source.minX) / source.width
        let y = (frame.minY - source.minY) / source.height
        return CGRect(
            x: destination.minX + x * destination.width,
            y: destination.minY + y * destination.height,
            width: frame.width,
            height: frame.height
        )
    }

    // The same flip converts in either direction between AX and AppKit coordinates.
    static func flippedFrame(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        // NSScreen.screens[0] is the primary display, whose origin is (0, 0).
        let maxY = screens.first?.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestIndex = index
                bestArea = area
            }
        }
        return bestIndex
    }
}
