import AVFoundation

/// Abstraction over the camera pipeline so CameraViewModel never touches AVFoundation
/// directly and can be unit tested with a mock. CaptureConfiguration is the single
/// source of truth for capture intent; Phase 3+ extend it rather than adding methods here.
protocol CameraServicing: AnyObject {
    var session: AVCaptureSession { get }
    var activeConfiguration: CaptureConfiguration { get }
    var activeDeviceName: String { get }
    var capabilities: CameraCapabilities { get }

    func requestCameraAuthorization() async -> Bool
    func configureSession(with configuration: CaptureConfiguration) throws -> CaptureConfiguration
    func startSession()
    func stopSession()

    /// Applies a changed configuration. Runs off the main thread and reports back
    /// the configuration CameraService actually applied (values get clamped to the
    /// active device's ranges, and unsupported modes fall back to auto) so the
    /// caller's published state never claims a setting that isn't really active.
    func updateConfiguration(_ configuration: CaptureConfiguration, completion: @escaping (Result<CaptureConfiguration, CameraError>) -> Void)

    /// Captures using activeConfiguration.photoFormat. Reports back what was
    /// actually captured (AVCapturePhoto.isRawPhoto is the ground truth), never
    /// claiming RAW/ProRAW succeeded when the device silently returned processed.
    func capturePhoto(completion: @escaping (Result<CapturedPhoto, CameraError>) -> Void)

    /// Captures `settings.frameCount` frames (always .processed — RAW/ProRAW
    /// bursts are impractically large for this), stacking them via FrameStacker
    /// as each one arrives rather than holding every frame in memory at once.
    /// Cooperative cancellation via Task.checkCancellation() between frames.
    func captureMultiFrameBurst(settings: MultiFrameCaptureSettings, progress: @escaping (Int, Int) -> Void) async throws -> MultiFrameCaptureResult

    /// Captures `settings.frameCount` frames at different exposure-bias offsets
    /// centered on whatever bias is currently active, restoring it afterward.
    /// Each frame is returned individually — not merged.
    func captureExposureBracket(settings: BracketSettings, progress: @escaping (Int, Int) -> Void) async throws -> [CapturedPhoto]
}
