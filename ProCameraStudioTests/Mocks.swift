import AVFoundation
@testable import ProCameraStudio

final class MockCameraService: CameraServicing {
    let session = AVCaptureSession()
    private(set) var activeConfiguration = CaptureConfiguration()
    var activeDeviceName = "Mock Camera"
    var capabilities = CameraCapabilities(
        minISO: 32, maxISO: 3200,
        minExposureDurationSeconds: 1.0 / 8000, maxExposureDurationSeconds: 1.0,
        minExposureTargetBias: -2, maxExposureTargetBias: 2,
        minWhiteBalanceKelvin: 2000, maxWhiteBalanceKelvin: 10000,
        supportsManualFocus: true,
        availableLenses: [.ultraWide, .wide, .telephoto]
    )
    var capturedPhotoResult: Result<Data, CameraError> = .success(Data([0x01]))

    private(set) var didStartSession = false
    private(set) var didStopSession = false

    private let authorized: Bool

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestCameraAuthorization() async -> Bool { authorized }

    func configureSession(with configuration: CaptureConfiguration) throws -> CaptureConfiguration {
        activeConfiguration = configuration
        return activeConfiguration
    }

    func startSession() { didStartSession = true }
    func stopSession() { didStopSession = true }

    func updateConfiguration(_ configuration: CaptureConfiguration, completion: @escaping (Result<CaptureConfiguration, CameraError>) -> Void) {
        activeConfiguration = configuration
        completion(.success(activeConfiguration))
    }

    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void) {
        completion(capturedPhotoResult)
    }
}

final class MockMediaStorage: MediaStoring {
    private let authorized: Bool
    private(set) var savedData: Data?

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestAddOnlyAuthorization() async -> Bool { authorized }

    func savePhotoData(_ data: Data, completion: @escaping (Result<Void, CameraError>) -> Void) {
        savedData = data
        completion(.success(()))
    }
}
