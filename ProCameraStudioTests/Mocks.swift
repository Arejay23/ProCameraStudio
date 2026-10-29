import AVFoundation
@testable import ProCameraStudio

final class MockCameraService: CameraServicing {
    let session = AVCaptureSession()
    private(set) var activeConfiguration = CaptureConfiguration()
    var activeDeviceName = "Mock Camera"
    var capturedPhotoResult: Result<Data, CameraError> = .success(Data([0x01]))

    private(set) var didStartSession = false
    private(set) var didStopSession = false

    private let authorized: Bool

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestCameraAuthorization() async -> Bool { authorized }

    func configureSession(with configuration: CaptureConfiguration) throws {
        activeConfiguration = configuration
    }

    func startSession() { didStartSession = true }
    func stopSession() { didStopSession = true }

    func updateConfiguration(_ configuration: CaptureConfiguration) throws {
        activeConfiguration = configuration
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
