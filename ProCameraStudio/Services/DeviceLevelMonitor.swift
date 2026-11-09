import CoreMotion

/// Continuous roll-angle monitoring for the level indicator — separate from
/// MotionMonitor (Phase 4), which only runs during multi-frame capture.
/// This runs whenever the camera screen is visible.
@MainActor
final class DeviceLevelMonitor: ObservableObject {
    @Published private(set) var rollDegrees: Double = 0

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 15.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.rollDegrees = motion.attitude.roll * 180 / .pi
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        rollDegrees = 0
    }
}
