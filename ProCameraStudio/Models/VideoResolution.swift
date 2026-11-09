import AVFoundation

enum VideoResolution: String, CaseIterable, Hashable {
    case hd1080p
    case uhd4K

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080p: return .hd1920x1080
        case .uhd4K: return .hd4K3840x2160
        }
    }

    var displayName: String {
        switch self {
        case .hd1080p: return "1080p"
        case .uhd4K: return "4K"
        }
    }

    /// Nominal pixel dimensions for the preset — what was requested/applied
    /// via the session, not measured from the output file.
    var pixelDimensions: (width: Int, height: Int) {
        switch self {
        case .hd1080p: return (1920, 1080)
        case .uhd4K: return (3840, 2160)
        }
    }
}
