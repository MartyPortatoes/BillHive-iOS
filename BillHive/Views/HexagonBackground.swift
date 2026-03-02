import SwiftUI

// MARK: - Hex Grid Background

/// Draws the same repeating honeycomb pattern used on the web app's body background.
/// Tiles a 168×300 pt cell (3× the web SVG tile) with amber strokes at 6% opacity.
struct HexagonBackground: View {
    var body: some View {
        Canvas { context, size in
            let tileW: CGFloat = 168
            let tileH: CGFloat = 300
            let cols = Int(ceil(size.width  / tileW)) + 2
            let rows = Int(ceil(size.height / tileH)) + 2
            let color = Color.bhAmber.opacity(0.06)

            var path = Path()

            for row in -1 ..< rows {
                for col in -1 ..< cols {
                    let dx = CGFloat(col) * tileW
                    let dy = CGFloat(row) * tileH

                    // Upper hex in tile  (scaled 3× from web SVG: M84 198L0 150L0 48L84 0L168 48L168 150Z)
                    path.move(to:    CGPoint(x: dx+84,  y: dy+198))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+150))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+48))
                    path.addLine(to: CGPoint(x: dx+84,  y: dy+0))
                    path.addLine(to: CGPoint(x: dx+168, y: dy+48))
                    path.addLine(to: CGPoint(x: dx+168, y: dy+150))
                    path.closeSubpath()

                    // Lower connector hex in tile  (M84 300L0 252L0 204L84 156L168 204L168 252Z)
                    path.move(to:    CGPoint(x: dx+84,  y: dy+300))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+252))
                    path.addLine(to: CGPoint(x: dx+0,   y: dy+204))
                    path.addLine(to: CGPoint(x: dx+84,  y: dy+156))
                    path.addLine(to: CGPoint(x: dx+168, y: dy+204))
                    path.addLine(to: CGPoint(x: dx+168, y: dy+252))
                    path.closeSubpath()
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 0.75)
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
