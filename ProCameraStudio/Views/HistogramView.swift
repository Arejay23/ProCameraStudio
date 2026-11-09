import SwiftUI

/// Small RGB histogram overlay. Filled, semi-transparent curves per channel —
/// the standard camera-app histogram presentation.
struct HistogramView: View {
    let data: HistogramData

    var body: some View {
        Canvas { context, size in
            drawChannel(data.red, color: .red, context: context, size: size)
            drawChannel(data.green, color: .green, context: context, size: size)
            drawChannel(data.blue, color: .blue, context: context, size: size)
        }
        .frame(width: 120, height: 60)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    private func drawChannel(_ bins: [Float], color: Color, context: GraphicsContext, size: CGSize) {
        guard bins.count > 1 else { return }
        var path = Path()
        let stepX = size.width / CGFloat(bins.count - 1)
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in bins.enumerated() {
            let x = CGFloat(index) * stepX
            let y = size.height - CGFloat(value) * size.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.35)))
        context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1)
    }
}
