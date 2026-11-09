/// How a multi-frame burst is merged into one image. These are the only two
/// genuinely different algorithms Phase 4 implements — the four user-facing
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
    case lightning

    /// Lightning needs the same algorithm as Star Trails, not Long Exposure's
    /// averaging: a brief bright flash that only appears in one of many
    /// frames would be averaged down to a fraction of its real brightness —
    /// "lighten" compositing (keep the brightest value per pixel) is what
    /// keeps the flash at full brightness in the final image.
    var algorithm: StackingAlgorithm {
        switch self {
        case .starTrails, .lightning: return .maximum
        case .noiseReduction, .longExposure: return .average
        }
    }

    /// Long Exposure, Star Trails, and Lightning all run until the user taps
    /// Stop — matching how real cameras handle bulb-mode/star-trail/lightning
    /// capture, where duration is a creative choice, not a fixed preset.
    /// Noise Reduction stays a short, fixed burst, since that's a quick
    /// denoise operation, not an open-ended one.
    var isUnbounded: Bool {
        self != .noiseReduction
    }

    var defaultFrameCount: Int {
        switch self {
        case .noiseReduction: return 6
        case .longExposure: return 10
        case .starTrails: return 20
        case .lightning: return 20
        }
    }

    /// Safety ceiling for unbounded modes only — stops a runaway capture
    /// (e.g. the user walks away without tapping Stop) from eating
    /// storage/battery indefinitely. Not shown to the user as a target.
    var maximumUnboundedFrameCount: Int {
        switch self {
        case .starTrails: return 1800 // ~30 min at the 1s interval below
        case .longExposure: return 600 // ~5 min at the 0.3s interval below
        case .lightning: return 3600 // ~10 min at the 0.1s requested interval, plus real per-frame overhead
        case .noiseReduction: return defaultFrameCount
        }
    }

    var defaultIntervalSeconds: Double {
        switch self {
        case .noiseReduction: return 0.2
        case .longExposure: return 0.3
        case .starTrails: return 1.0
        // As short as practical — real per-frame capture/processing time
        // still adds a gap this can't eliminate (see explanation below).
        case .lightning: return 0.1
        }
    }

    var displayName: String {
        switch self {
        case .noiseReduction: return "Noise Reduction"
        case .longExposure: return "Long Exposure"
        case .starTrails: return "Star Trails"
        case .lightning: return "Lightning"
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
        case .lightning:
            return "Same technique as Star Trails: keeps the brightest value at each pixel, so a flash in any one frame stays at full brightness in the final image instead of being averaged away. There's a brief gap between frames, so very short flashes can be missed — this isn't a true continuous exposure with zero dead time."
        }
    }

    var bestSettingsTip: String {
        switch self {
        case .noiseReduction:
            return "Best for: low light, handheld. Keep the subject still — this blends frames shot moments apart, so motion will blur. No tripod required, but steadier is better."
        case .longExposure:
            return "Best for: light trails, flowing water, moving clouds. Use a tripod — the blur only looks intentional when the camera itself stays still. Runs until you tap Stop; a few seconds is often enough."
        case .starTrails:
            return "Best for: a clear night sky, away from city light pollution. Requires a tripod — any camera movement breaks the trail effect. Runs until you tap Stop — longer runs make longer trails, so a few minutes is typical."
        case .lightning:
            return "Best for: storms with frequent strikes, shot from a safe distance. Use a tripod and frame the area where lightning is occurring. Runs until you tap Stop — leave it running through the storm; every flash it catches stays in the final image."
        }
    }
}
