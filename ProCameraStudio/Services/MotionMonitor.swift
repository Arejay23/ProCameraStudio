import CoreMotion
import Combine

/// Lightweight stability check for multi-frame capture — not full image
/// registration/alignment (see FrameStacker), just a "hold steady" signal so
/// the user knows handheld shake will hurt the stacked result.
@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var isStable = true

    private let motionManager = CMMotionManager()
    private let rotationRateThreshold = 0.15 // rad/s, empirical

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rate = motion.rotationRate
            let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            self.isStable = magnitude < self.rotationRateThreshold
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isStable = true
    }
}
