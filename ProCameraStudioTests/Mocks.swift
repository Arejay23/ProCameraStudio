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

    /// When > 0, simulates a slow unbounded capture so tests can cancel
    /// mid-run and verify stopping finalizes with what's captured so far
    /// rather than discarding it (cancellation here is cooperative, same as
    /// the real CameraService — it never throws).
    var multiFrameBurstDelayNanoseconds: UInt64 = 0

    func captureMultiFrameBurst(settings: MultiFrameCaptureSettings, progress: @escaping (Int, Int) -> Void) async throws -> MultiFrameCaptureResult {
        for index in 1...max(settings.frameCount, 1) {
            if multiFrameBurstDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: multiFrameBurstDelayNanoseconds)
            }
            if Task.isCancelled { break }
            progress(index, settings.isUnbounded ? 0 : settings.frameCount)
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

    var focusStackResult: Result<[CapturedPhoto], CameraError> = .success([])

    func captureFocusStack(settings: FocusStackSettings, progress: @escaping (Int, Int) -> Void) async throws -> [CapturedPhoto] {
        for index in 1...max(settings.frameCount, 1) {
            progress(index, settings.frameCount)
        }
        switch focusStackResult {
        case .success(let frames): return frames
        case .failure(let error): throw error
        }
    }

    var videoCapabilities = VideoCapabilities(
        availableResolutions: [.hd1080p, .uhd4K],
        availableFrameRates: [24, 30, 60],
        supportsProRes: true
    )
    private(set) var isRecording = false
    var currentRecordingFileSizeBytes = 0
    var micAuthorized = true
    var recordedVideoResult: Result<RecordedVideo, CameraError> = .success(
        RecordedVideo(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("mock.mov"),
            duration: 5.5,
            fileSizeBytes: 12_000_000,
            resolution: .hd1080p,
            usedProRes: false
        )
    )

    func requestMicrophoneAuthorization() async -> Bool { micAuthorized }

    func startRecording() throws {
        isRecording = true
    }

    func stopRecording(completion: @escaping (Result<RecordedVideo, CameraError>) -> Void) {
        isRecording = false
        completion(recordedVideoResult)
    }

    private(set) var isHistogramEnabled = false

    func setHistogramEnabled(_ enabled: Bool, update: @escaping (HistogramData) -> Void) {
        isHistogramEnabled = enabled
    }
}

final class MockMediaStorage: MediaStoring {
    private let authorized: Bool
    private(set) var savedData: Data?
    private(set) var savedDataHistory: [Data] = []
    private(set) var savedVideoURL: URL?

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func requestAddOnlyAuthorization() async -> Bool { authorized }

    func savePhotoData(_ data: Data, completion: @escaping (Result<Void, CameraError>) -> Void) {
        savedData = data
        savedDataHistory.append(data)
        completion(.success(()))
    }

    func saveVideo(at url: URL, completion: @escaping (Result<Void, CameraError>) -> Void) {
        savedVideoURL = url
        completion(.success(()))
    }
}

final class MockLibraryStore: LibraryStoring {
    private(set) var items: [LibraryItemRecord] = []
    private(set) var addPhotoCallCount = 0
    private(set) var addVideoCallCount = 0

    @discardableResult
    func addPhoto(
        data: Data,
        kind: LibraryItemKind,
        width: Int,
        height: Int,
        formatLabel: String,
        iso: Double?,
        exposureTimeSeconds: Double?,
        fNumber: Double?,
        originals: [Data]
    ) -> LibraryItemRecord? {
        addPhotoCallCount += 1
        let record = LibraryItemRecord(
            id: UUID(),
            kind: kind,
            captureDate: Date(),
            mediaFileName: "mock.heic",
            thumbnailFileName: "mock_thumb.jpg",
            width: width,
            height: height,
            fileSizeBytes: data.count,
            formatLabel: formatLabel,
            iso: iso,
            exposureTimeSeconds: exposureTimeSeconds,
            fNumber: fNumber,
            durationSeconds: nil,
            originalFileNames: originals.isEmpty ? [] : (0..<originals.count).map { "\($0).heic" },
            editFileName: nil
        )
        items.insert(record, at: 0)
        return record
    }

    @discardableResult
    func addVideo(fileURL: URL, width: Int, height: Int, durationSeconds: Double, formatLabel: String) -> LibraryItemRecord? {
        addVideoCallCount += 1
        let record = LibraryItemRecord(
            id: UUID(),
            kind: .video,
            captureDate: Date(),
            mediaFileName: "mock.mov",
            thumbnailFileName: "mock_thumb.jpg",
            width: width,
            height: height,
            fileSizeBytes: 0,
            formatLabel: formatLabel,
            iso: nil,
            exposureTimeSeconds: nil,
            fNumber: nil,
            durationSeconds: durationSeconds,
            originalFileNames: [],
            editFileName: nil
        )
        items.insert(record, at: 0)
        return record
    }

    func mediaURL(for item: LibraryItemRecord) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(item.mediaFileName) }
    func originalMediaURLs(for item: LibraryItemRecord) -> [URL] { [] }
    func thumbnailURL(for item: LibraryItemRecord) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(item.thumbnailFileName) }
    func editedMediaURL(for item: LibraryItemRecord) -> URL? { nil }

    @discardableResult
    func saveEdit(for item: LibraryItemRecord, editedData: Data) -> LibraryItemRecord? { nil }
    @discardableResult
    func revertEdit(for item: LibraryItemRecord) -> LibraryItemRecord? { nil }
    func delete(_ item: LibraryItemRecord) {
        items.removeAll { $0.id == item.id }
    }
}
