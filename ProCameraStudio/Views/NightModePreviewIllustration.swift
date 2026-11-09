import SwiftUI

/// A small, deliberately stylized illustration of what each stacking mode's
/// result tends to look like — not a real captured photo. No sample photos
/// are bundled with the app, so this is a quick visual cue drawn with shapes,
/// clearly abstract rather than claiming to be an actual example photograph.
struct NightModePreviewIllustration: View {
    let mode: NightCaptureMode

    var body: some View {
        Canvas { context, size in
            switch mode {
            case .noiseReduction:
                drawNoiseReduction(context, size)
            case .longExposure:
                drawLongExposure(context, size)
            case .starTrails:
                drawStarTrails(context, size)
            case .lightning:
                drawLightning(context, size)
            }
        }
        .frame(width: 88, height: 60)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func drawNoiseReduction(_ context: GraphicsContext, _ size: CGSize) {
        let dotPositions: [(CGFloat, CGFloat)] = [
            (6, 10), (14, 22), (9, 38), (20, 14), (24, 44), (16, 30),
            (10, 50), (26, 26), (4, 24), (22, 8)
        ]
        for (x, y) in dotPositions {
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2))
            context.fill(dot, with: .color(.white.opacity(0.7)))
        }
        let smoothRect = CGRect(x: size.width / 2 + 4, y: 6, width: size.width / 2 - 10, height: size.height - 12)
        context.fill(Path(roundedRect: smoothRect, cornerRadius: 6), with: .color(.white.opacity(0.55)))
    }

    private func drawLongExposure(_ context: GraphicsContext, _ size: CGSize) {
        let colors: [Color] = [.orange, .yellow, .orange.opacity(0.7)]
        for (index, color) in colors.enumerated() {
            var path = Path()
            let yBase = size.height * (0.25 + CGFloat(index) * 0.22)
            path.move(to: CGPoint(x: 4, y: yBase))
            path.addCurve(
                to: CGPoint(x: size.width - 4, y: yBase - 8),
                control1: CGPoint(x: size.width * 0.35, y: yBase + 10),
                control2: CGPoint(x: size.width * 0.65, y: yBase - 18)
            )
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }

    private func drawStarTrails(_ context: GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for radius in stride(from: 8.0, through: 26.0, by: 6.0) {
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(-30), endAngle: .degrees(160), clockwise: false)
            context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
        }
        let dot = Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        context.fill(dot, with: .color(.white))
    }

    private func drawLightning(_ context: GraphicsContext, _ size: CGSize) {
        var bolt = Path()
        let midX = size.width / 2
        bolt.move(to: CGPoint(x: midX + 10, y: 4))
        bolt.addLine(to: CGPoint(x: midX - 8, y: size.height * 0.5))
        bolt.addLine(to: CGPoint(x: midX + 4, y: size.height * 0.5))
        bolt.addLine(to: CGPoint(x: midX - 10, y: size.height - 4))
        bolt.addLine(to: CGPoint(x: midX + 6, y: size.height * 0.55))
        bolt.addLine(to: CGPoint(x: midX - 6, y: size.height * 0.55))
        bolt.closeSubpath()
        context.fill(bolt, with: .color(.yellow.opacity(0.9)))
        context.stroke(bolt, with: .color(.white.opacity(0.8)), lineWidth: 0.5)
    }
}
