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

    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void)
}
