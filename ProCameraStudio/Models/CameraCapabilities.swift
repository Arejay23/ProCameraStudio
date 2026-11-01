import Foundation

/// Valid manual-control ranges for the currently active device/format, discovered
/// at runtime rather than hardcoded since ultra-wide/main/telephoto on the 14 Pro
/// each report different ISO, shutter, and exposure-bias ranges.
///
/// White balance Kelvin bounds are the one exception: AVFoundation exposes a max
/// white-balance *gain*, not a documented Kelvin range, so these bounds are a
/// fixed, conventional UI range (clamped to the device's actual gain limits when
/// applied) rather than a device-reported one.
struct CameraCapabilities: Equatable {
    var minISO: Float
    var maxISO: Float
    var minExposureDurationSeconds: Double
    var maxExposureDurationSeconds: Double
    var minExposureTargetBias: Float
    var maxExposureTargetBias: Float
    var minWhiteBalanceKelvin: Float
    var maxWhiteBalanceKelvin: Float
    var supportsManualFocus: Bool
    var availableLenses: [LensType]

    static let fallback = CameraCapabilities(
        minISO: 0,
        maxISO: 0,
        minExposureDurationSeconds: 0,
        maxExposureDurationSeconds: 0,
        minExposureTargetBias: 0,
        maxExposureTargetBias: 0,
        minWhiteBalanceKelvin: 2000,
        maxWhiteBalanceKelvin: 10000,
        supportsManualFocus: false,
        availableLenses: []
    )
}
