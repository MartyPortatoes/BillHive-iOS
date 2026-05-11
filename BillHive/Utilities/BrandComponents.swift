import SwiftUI

// MARK: - Tri-Hex Logo Mark

/// Three-hexagon logo matching the BillHive website SVG (viewBox 100x100).
///
/// Draws three filled hexagons in an asymmetric cluster: one on the left,
/// one top-right, and one bottom-right, all in the brand amber color.
struct TriHexLogoMark: View {
    let size: CGFloat

    /// Scales SVG points from the 100x100 viewBox to the requested `size`.
    private func hex(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        let scaled = pts.map { CGPoint(x: $0.0 / 100 * size, y: $0.1 / 100 * size) }
        path.move(to: scaled[0])
        scaled.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    var body: some View {
        ZStack {
            hex([(48.6,50),(41.2,62.8),(26.4,62.8),(19,50),(26.4,37.2),(41.2,37.2)])
                .fill(Color.bhAmber)
            hex([(72.9,36),(65.5,48.8),(50.7,48.8),(43.3,36),(50.7,23.2),(65.5,23.2)])
                .fill(Color.bhAmber)
            hex([(72.9,64),(65.5,76.8),(50.7,76.8),(43.3,64),(50.7,51.2),(65.5,51.2)])
                .fill(Color.bhAmber)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Hex Logo Mark

/// A single hexagon with a stylized "bill" icon inside — three horizontal
/// bars of decreasing width, resembling a receipt or invoice.
struct HexLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            HexShape()
                .fill(Color.bhAmber)
                .frame(width: size, height: size * CGFloat(3).squareRoot() / 2)
            VStack(spacing: size * 0.06) {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.45, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.6, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.35, height: size * 0.09)
            }
        }
    }
}

// MARK: - Hex Shape

/// A flat-top regular hexagon shape that fills the given rect.
struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let points: [CGPoint] = [
            CGPoint(x: w * 0.25, y: 0),
            CGPoint(x: w * 0.75, y: 0),
            CGPoint(x: w, y: h * 0.5),
            CGPoint(x: w * 0.75, y: h),
            CGPoint(x: w * 0.25, y: h),
            CGPoint(x: 0, y: h * 0.5)
        ]
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Button Styles

/// Solid amber background with dark text. Used for primary call-to-action buttons.
struct BHPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.semibold))
            .foregroundColor(Color(hex: "#0c0d0f"))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(isEnabled ? Color.bhAmber : Color.bhAmber.opacity(0.4))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Surface-colored background with a border outline. Used for secondary actions.
struct BHSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.medium))
            .foregroundColor(.bhText)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Surface background with a red border and red text. Used for destructive actions.
struct BHDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.medium))
            .foregroundColor(.bhRed)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhRed, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
