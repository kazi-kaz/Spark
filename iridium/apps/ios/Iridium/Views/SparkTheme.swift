import SwiftUI

/// Spark's brand colors and bolt mark. Views read these instead of
/// hard-coding colors so the look stays consistent.
enum SparkTheme {
    /// Brand amber (#FFB627): primary actions, the selected tab, the bolt.
    static let accent = Color(red: 1.0, green: 0.714, blue: 0.153)
    /// Near-black ground (#08090C) behind every screen.
    static let ground = Color(red: 0.031, green: 0.035, blue: 0.047)
    /// Card surface (#14161B).
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.106)
    /// Raised control surface (#1C1F26).
    static let raised = Color(red: 0.110, green: 0.122, blue: 0.149)
    /// "Runs well" status (#8FE3C0).
    static let good = Color(red: 0.561, green: 0.890, blue: 0.753)
    /// Problem status (#FF9A85). Kept apart from the accent so amber never means an error.
    static let problem = Color(red: 1.0, green: 0.604, blue: 0.522)
    /// Text drawn on top of the accent (#17120D).
    static let onAccent = Color(red: 0.090, green: 0.071, blue: 0.051)
}

/// The Spark lightning bolt, drawn in a centered square inside `rect`.
struct SparkBolt: Shape {
    private static let outline: [CGPoint] = [
        CGPoint(x: 0.60, y: 0.06), CGPoint(x: 0.22, y: 0.56), CGPoint(x: 0.46, y: 0.56),
        CGPoint(x: 0.38, y: 0.94), CGPoint(x: 0.78, y: 0.42), CGPoint(x: 0.53, y: 0.42),
    ]

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        var path = Path()
        for (index, point) in Self.outline.enumerated() {
            let scaled = CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        path.closeSubpath()
        return path
    }
}

/// Bolt in the brand accent, sized by its frame. Decorative unless a label is given.
struct SparkMark: View {
    var size: CGFloat = 20

    var body: some View {
        SparkBolt()
            .fill(SparkTheme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
