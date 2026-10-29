import AVFoundation

/// Abstraction over the camera pipeline so CameraViewModel never touches AVFoundation
/// directly and can be unit tested with a mock. Phase 2+ extend CaptureConfiguration
/// and add methods here rather than reshaping this protocol.
protocol CameraServicing: AnyObject {
    var session: AVCaptureSession { get }
    var activeConfiguration: CaptureConfiguration { get }
    var activeDeviceName: String { get }

    func requestCameraAuthorization() async -> Bool
    func configureSession(with configuration: CaptureConfiguration) throws
    func startSession()
    func stopSession()
    func updateConfiguration(_ configuration: CaptureConfiguration) throws
    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void)
}
