import SwiftUI

// MARK: - Hex Grid Background

/// Draws the same repeating honeycomb pattern used on the web app's body background.
/// Tiles a 126×225 pt cell (1.5× the web SVG tile) with amber strokes at 4% opacity.
struct HexagonBackground: View {
    var body: some View {
        Canvas { context, size in
            let tileW: CGFloat = 126
            let tileH: CGFloat = 225
            let cols = Int(ceil(size.width  / tileW)) + 2
            let rows = Int(ceil(size.height / tileH)) + 2
            let color = Color.bhAmber.opacity(0.04)

            var path = Path()

            for row in -1 ..< rows {
                for col in -1 ..< cols {
                    let dx = CGFloat(col) * tileW
                    let dy = CGFloat(row) * tileH

                    // Upper hex in tile  (scaled 1.5× from web SVG 84×150)
                    path.move(to:    CGPoint(x: dx+63,  y: dy+148.5))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+112.5))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+36))
                    path.addLine(to: CGPoint(x: dx+63,  y: dy+0))
                    path.addLine(to: CGPoint(x: dx+126, y: dy+36))
                    path.addLine(to: CGPoint(x: dx+126, y: dy+112.5))
                    path.closeSubpath()

                    // Lower connector hex in tile
                    path.move(to:    CGPoint(x: dx+63,  y: dy+225))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+189))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+153))
                    path.addLine(to: CGPoint(x: dx+63,  y: dy+117))
                    path.addLine(to: CGPoint(x: dx+126, y: dy+153))
                    path.addLine(to: CGPoint(x: dx+126, y: dy+189))
                    path.closeSubpath()
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
    }
}

// MARK: - Composite background (solid + pattern)

/// Drop-in replacement for `Color.bhBackground.ignoresSafeArea()`.
/// Stacks the solid background colour underneath the hex grid.
struct HexBGView: View {
    var body: some View {
        ZStack {
            Color.bhBackground
            HexagonBackground()
        }
    }
}
