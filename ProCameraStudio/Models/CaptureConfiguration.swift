import AVFoundation

/// The physical lens to use on the back camera system. iPhone 14 Pro's front
/// camera only has a wide lens, so CameraService falls back to .wide there.
enum LensType: String, CaseIterable, Hashable {
    case ultraWide
    case wide
    case telephoto

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }

    var displayName: String {
        switch self {
        case .ultraWide: return "0.5x"
        case .wide: return "1x"
        case .telephoto: return "3x"
        }
    }
}

/// Single source of truth for capture intent. CameraServicing methods take/return
/// this whole struct rather than individual parameters, so Phase 3+ extend it
/// instead of reshaping the protocol. Manual fields are Optional: nil means
/// "follow auto."
struct CaptureConfiguration: Equatable {
    var position: AVCaptureDevice.Position = .back
    var lensType: LensType = .wide
    var photoFormat: PhotoFormat = .processed

    // If either is non-nil, exposure mode is .custom.
    var manualISO: Float?
    var manualExposureDuration: CMTime?

    // EV compensation, applied on top of whichever exposure mode is active.
    var exposureBias: Float?

    // Manual focus (device lens position, 0 = near limit, 1 = far limit).
    var manualFocusLensPosition: Float?

    // Manual white balance as color temperature in Kelvin, for a UI-friendly
    // slider; CameraService converts this to device gains.
    var manualWhiteBalanceKelvin: Float?

    // Tap-to-focus / tap-to-meter points, in device coordinates (0...1, 0...1).
    var focusPointOfInterest: CGPoint?
    var exposurePointOfInterest: CGPoint?

    // Lock the current auto value without pinning to a specific number.
    var isExposureLocked: Bool = false
    var isFocusLocked: Bool = false

    var isManualExposureEnabled: Bool { manualISO != nil || manualExposureDuration != nil }
}
