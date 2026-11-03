/// Resolutions/frame rates are checked live against the session
/// (`canSetSessionPreset`) and active format (`videoSupportedFrameRateRanges`)
/// rather than assumed. `supportsProRes` reflects
/// `AVCaptureMovieFileOutput.availableVideoCodecTypes`, which is only
/// meaningful once the movie output is actually connected — i.e. only once
/// already in video mode, not before switching to it.
struct VideoCapabilities: Equatable {
    var availableResolutions: [VideoResolution]
    var availableFrameRates: [Double]
    var supportsProRes: Bool

    static let fallback = VideoCapabilities(availableResolutions: [], availableFrameRates: [], supportsProRes: false)
}
