import SwiftUI

/// A horizontal line that rotates with device tilt and turns green within
/// ~1° of level — a bubble-level substitute that doesn't need a gyroscope
/// visualization more elaborate than a camera app actually benefits from.
struct LevelIndicatorView: View {
    let rollDegrees: Double

    private var isLevel: Bool { abs(rollDegrees) < 1.0 }

    var body: some View {
        Rectangle()
            .fill(isLevel ? Color.green : Color.white)
            .frame(width: 60, height: 2)
            .shadow(radius: 2)
            .rotationEffect(.degrees(-rollDegrees))
            .animation(.linear(duration: 0.1), value: rollDegrees)
            .allowsHitTesting(false)
    }
}
