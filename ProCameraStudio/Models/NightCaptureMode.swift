/// How a multi-frame burst is merged into one image. These are the only two
/// genuinely different algorithms Phase 4 implements — the three user-facing
/// modes below are presets over them, not separate techniques.
enum StackingAlgorithm: Equatable {
    case average
    case maximum
}

/// User-facing multi-frame capture presets. None of these are a true longer
/// sensor exposure — the sensor still only exposes each frame briefly; the
/// effect comes entirely from combining multiple frames computationally.
/// `explanation` is surfaced directly in the UI so that's never left implicit.
enum NightCaptureMode: String, CaseIterable, Hashable {
    case noiseReduction
    case longExposure
    case starTrails

    var algorithm: StackingAlgorithm {
        self == .starTrails ? .maximum : .average
    }

    var defaultFrameCount: Int {
        switch self {
        case .noiseReduction: return 6
        case .longExposure: return 10
        case .starTrails: return 20
        }
    }

    var defaultIntervalSeconds: Double {
        switch self {
        case .noiseReduction: return 0.2
        case .longExposure: return 0.3
        case .starTrails: return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .noiseReduction: return "Noise Reduction"
        case .longExposure: return "Long Exposure"
        case .starTrails: return "Star Trails"
        }
    }

    var explanation: String {
        switch self {
        case .noiseReduction:
            return "Averages several quick frames to reduce low-light noise. Computational — not a longer sensor exposure."
        case .longExposure:
            return "Averages a burst of frames over time to simulate motion blur and light trails. Computational — the sensor itself never exposes for longer than one frame."
        case .starTrails:
            return "Keeps the brightest value seen at each pixel across many frames, so moving points of light leave trails without the sky washing out. Computational stacking, not one long sensor exposure."
        }
    }

    var bestSettingsTip: String {
        switch self {
        case .noiseReduction:
            return "Best for: low light, handheld. Keep the subject still — this blends frames shot moments apart, so motion will blur. No tripod required, but steadier is better."
        case .longExposure:
            return "Best for: light trails, flowing water, moving clouds. Use a tripod — the blur only looks intentional when the camera itself stays still."
        case .starTrails:
            return "Best for: a clear night sky, away from city light pollution. Requires a tripod — any camera movement breaks the trail effect. Longer capture = longer trails; try the default 20 frames first."
        }
    }
}
