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
        availableLenses: [.ultraWide, .wide, .telephoto],
        supportsRAW: true,
        supportsAppleProRAW: true
    )
    var capturedPhotoResult: Result<CapturedPhoto, CameraError> = .success(
        CapturedPhoto(
            data: Data([0x01]),
            isRaw: false,
            width: 4032,
            height: 3024,
            fileSizeBytes: 4_200_000,
            requestedFormat: .processed,
            iso: 100,
            exposureTimeSeconds: 1.0 / 120,
            fNumber: 1.78
        )
    )

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

    func capturePhoto(completion: @escaping (Result<CapturedPhoto, CameraError>) -> Void) {
        completion(capturedPhotoResult)
    }

    var multiFrameResult: Result<MultiFrameCaptureResult, CameraError> = .success(
        MultiFrameCaptureResult(
            stacked: CapturedPhoto(
                data: Data([0x03]),
                isRaw: false,
                width: 4032,
                height: 3024,
                fileSizeBytes: 5_000_000,
                requestedFormat: .processed,
                iso: nil,
                exposureTimeSeconds: nil,
                fNumber: nil
            ),
            originalFrames: []
        )
    )

    func captureMultiFrameBurst(settings: MultiFrameCaptureSettings, progress: @escaping (Int, Int) -> Void) async throws -> MultiFrameCaptureResult {
        for index in 1...max(settings.frameCount, 1) {
            progress(index, settings.frameCount)
        }
        switch multiFrameResult {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    var bracketResult: Result<[CapturedPhoto], CameraError> = .success([])

    func captureExposureBracket(settings: BracketSettings, progress: @escaping (Int, Int) -> Void) async throws -> [CapturedPhoto] {
        for index in 1...max(settings.frameCount, 1) {
            progress(index, settings.frameCount)
        }
        switch bracketResult {
        case .success(let frames): return frames
        case .failure(let error): throw error
        }
    }
}

final class MockMediaStorage: MediaStoring {
    private let authorized: Bool
    private(set) var savedData: Data?
    private(set) var savedDataHistory: [Data] = []

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestAddOnlyAuthorization() async -> Bool { authorized }

    func savePhotoData(_ data: Data, completion: @escaping (Result<Void, CameraError>) -> Void) {
        savedData = data
        savedDataHistory.append(data)
        completion(.success(()))
    }
}
