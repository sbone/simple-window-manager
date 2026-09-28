import Foundation
import Testing
@testable import OptimalLayout

struct WindowGeometryTests {
    // Offset bounds stand in for a left-hand display with menu bar and Dock insets.
    let usable = CGRect(x: -1200, y: 40, width: 1000, height: 800)

    @Test func fullAndCenteredLayoutsUseUsableBounds() {
        var geometry = WindowGeometry()
        #expect(geometry.targetFrame(for: .one, usable: usable) == usable)
        #expect(geometry.targetFrame(for: .three, usable: usable) ==
                CGRect(x: -950, y: 40, width: 500, height: 800))
    }

    @Test func halvesStartLeftAndWrap() {
        var geometry = WindowGeometry()
        for x in [-1200.0, -700, -1200, -700, -1200] {
            #expect(geometry.targetFrame(for: .two, usable: usable) ==
                    CGRect(x: x, y: 40, width: 500, height: 800))
        }
    }

    @Test func quadrantsStartUpperLeftAndCycleClockwise() {
        var geometry = WindowGeometry()
        let origins: [CGPoint] = [
            CGPoint(x: -1200, y: 440), CGPoint(x: -700, y: 440),
            CGPoint(x: -700, y: 40), CGPoint(x: -1200, y: 40)
        ]
        for origin in origins + origins + [origins[0]] {
            #expect(geometry.targetFrame(for: .four, usable: usable) ==
                    CGRect(origin: origin, size: CGSize(width: 500, height: 400)))
        }
    }

    @Test func cyclesAreIndependentAndNewSessionResetsThem() {
        var geometry = WindowGeometry()
        _ = geometry.targetFrame(for: .two, usable: usable)
        _ = geometry.targetFrame(for: .four, usable: usable)
        _ = geometry.targetFrame(for: .one, usable: usable)
        _ = geometry.targetFrame(for: .three, usable: usable)
        #expect(geometry.targetFrame(for: .two, usable: usable).minX == -700)
        #expect(geometry.targetFrame(for: .four, usable: usable).origin == CGPoint(x: -700, y: 440))
        // A different screen/window still uses the same command cycle.
        let other = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        #expect(geometry.targetFrame(for: .four, usable: other).origin == CGPoint(x: 800, y: 0))

        var restarted = WindowGeometry()
        #expect(restarted.targetFrame(for: .two, usable: usable).minX == -1200)
        #expect(restarted.targetFrame(for: .four, usable: usable).origin == CGPoint(x: -1200, y: 440))
    }

    @Test func fractionalSizesStayWithinUsableBounds() {
        let oddBounds = CGRect(x: 17.5, y: -713, width: 1011, height: 733)
        var geometry = WindowGeometry()
        for layout in Layout.allCases {
            for _ in 0..<4 {
                let frame = geometry.targetFrame(for: layout, usable: oddBounds)
                #expect(oddBounds.contains(frame))
                #expect(frame.width > 0 && frame.height > 0)
            }
        }
        #expect(geometry.targetFrame(for: .two, usable: oddBounds).width == 505.5)
    }

    @Test func displayTransferPreservesSizeAndRelativeOrigin() {
        let source = CGRect(x: 0, y: 40, width: 1000, height: 800)
        let destination = CGRect(x: -2000, y: 1000, width: 2000, height: 1200)
        let original = CGRect(x: 250, y: 240, width: 400, height: 300)
        let moved = WindowGeometry.movedFrame(original, from: source, to: destination)
        #expect(moved == CGRect(x: -1500, y: 1300, width: 400, height: 300))
        #expect(WindowGeometry.movedFrame(moved, from: destination, to: source) == original)
    }

    @Test func coordinateFlipUsesPrimaryDisplayEvenWithDisplayAbove() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let screens = [primary, above]
        let axFrame = CGRect(x: 100, y: 50, width: 500, height: 300)
        #expect(WindowGeometry.flippedFrame(axFrame, screens: screens) ==
                CGRect(x: 100, y: 550, width: 500, height: 300))
        let upperFrame = CGRect(x: 100, y: 1200, width: 500, height: 300)
        let upperAX = WindowGeometry.flippedFrame(upperFrame, screens: screens)
        #expect(upperAX == CGRect(x: 100, y: -600, width: 500, height: 300))
        #expect(WindowGeometry.flippedFrame(upperAX, screens: screens) == upperFrame)
    }

    @Test func displaySelectionUsesLargestOverlap() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                       CGRect(x: 1000, y: 0, width: 1600, height: 1000)]
        let straddling = CGRect(x: 950, y: 100, width: 600, height: 400)
        #expect(WindowGeometry.screenIndex(for: straddling, screens: screens) == 1)
        #expect(WindowGeometry.screenIndex(for: straddling, screens: screens.reversed()) == 0)
        #expect(WindowGeometry.screenIndex(for: CGRect(x: 750, y: 100, width: 500, height: 400),
                                          screens: screens) == 0) // Ties keep display order.
    }

    @Test func displaySelectionRequiresPositiveOverlap() {
        let frame = CGRect(x: -500, y: -500, width: 200, height: 100)
        #expect(WindowGeometry.screenIndex(for: frame, screens: []) == nil)
        #expect(WindowGeometry.screenIndex(for: frame, screens: [usable]) == nil)
        let touching = CGRect(x: usable.maxX, y: usable.minY, width: 200, height: 100)
        #expect(WindowGeometry.screenIndex(for: touching, screens: [usable]) == nil)
    }
}
