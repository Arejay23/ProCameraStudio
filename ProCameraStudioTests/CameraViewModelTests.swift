import XCTest
@testable import ProCameraStudio

final class CameraViewModelTests: XCTestCase {

    @MainActor
    func testStartGrantsAuthorizationAndStartsSession() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())

        await viewModel.start()

        XCTAssertEqual(viewModel.authorizationState, .authorized)
        XCTAssertTrue(cameraService.didStartSession)
        XCTAssertTrue(viewModel.isSessionRunning)
    }

    @MainActor
    func testStartWithDeniedAuthorizationDoesNotStartSession() async {
        let cameraService = MockCameraService(authorized: false)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())

        await viewModel.start()

        XCTAssertEqual(viewModel.authorizationState, .denied)
        XCTAssertFalse(cameraService.didStartSession)
    }

    @MainActor
    func testSwitchCameraTogglesPosition() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.switchCamera()

        XCTAssertEqual(cameraService.activeConfiguration.position, .front)
    }

    @MainActor
    func testSetManualISOUpdatesConfiguration() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.setManualISO(200)

        XCTAssertEqual(viewModel.configuration.manualISO, 200)
        XCTAssertEqual(cameraService.activeConfiguration.manualISO, 200)
    }

    @MainActor
    func testResetToAutoClearsManualOverrides() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()
        viewModel.setManualISO(400)
        viewModel.setManualFocus(0.3)

        viewModel.resetToAuto()

        XCTAssertNil(viewModel.configuration.manualISO)
        XCTAssertNil(viewModel.configuration.manualFocusLensPosition)
    }

    @MainActor
    func testFocusAndMeterClearsManualExposureAndFocus() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()
        viewModel.setManualISO(400)

        viewModel.focusAndMeter(at: CGPoint(x: 0.5, y: 0.5))

        XCTAssertNil(viewModel.configuration.manualISO)
        XCTAssertEqual(viewModel.configuration.focusPointOfInterest, CGPoint(x: 0.5, y: 0.5))
    }

    @MainActor
    func testSelectPhotoFormatUpdatesConfiguration() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.selectPhotoFormat(.appleProRAW)

        XCTAssertEqual(viewModel.configuration.photoFormat, .appleProRAW)
        XCTAssertEqual(cameraService.activeConfiguration.photoFormat, .appleProRAW)
    }

    @MainActor
    func testCapturePhotoReportsRAWFormat() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.capturedPhotoResult = .success(
            CapturedPhoto(
                data: Data([0x02]),
                isRaw: true,
                width: 8064,
                height: 6048,
                fileSizeBytes: 84_000_000,
                requestedFormat: .appleProRAW,
                iso: 64,
                exposureTimeSeconds: 1.0 / 60,
                fNumber: 1.78
            )
        )
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.capturePhoto()

        let gotInfo = await waitUntil { viewModel.lastCapture != nil }
        XCTAssertTrue(gotInfo)
        XCTAssertEqual(viewModel.lastCapture?.formatLabel, "Apple ProRAW")
        XCTAssertEqual(viewModel.lastCapture?.width, 8064)
    }

    @MainActor
    func testCapturePhotoSavesWhenAuthorized() async throws {
        let cameraService = MockCameraService(authorized: true)
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.capturePhoto()

        let didSave = await waitUntil { viewModel.didSavePhoto }
        XCTAssertTrue(didSave)
        XCTAssertNotNil(mediaStorage.savedData)
        XCTAssertFalse(viewModel.isCapturing)
    }

    @MainActor
    func testStartMultiFrameCaptureSavesStackedResult() async {
        let cameraService = MockCameraService(authorized: true)
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.startMultiFrameCapture(mode: .noiseReduction)

        let done = await waitUntil { viewModel.lastMultiFrameCapture != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(mediaStorage.savedDataHistory.count, 1)
        XCTAssertEqual(viewModel.lastMultiFrameCapture?.width, 4032)
    }

    /// Guards the real bug fixed in this phase: stopping an unbounded
    /// (Long Exposure/Star Trails) capture must finalize and save whatever
    /// was captured so far, not discard it the way a throwing
    /// CancellationError would.
    @MainActor
    func testCancellingUnboundedNightCaptureStillSavesResult() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.multiFrameBurstDelayNanoseconds = 30_000_000
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.startMultiFrameCapture(mode: .starTrails)
        try? await Task.sleep(nanoseconds: 80_000_000)
        viewModel.cancelMultiFrameCapture()

        let done = await waitUntil(timeout: 2.0) { viewModel.lastMultiFrameCapture != nil }
        XCTAssertTrue(done, "Stopping an unbounded capture should finalize and save a result, not discard it")
    }

    @MainActor
    func testStartExposureBracketSavesAllFrames() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.bracketResult = .success([
            CapturedPhoto(data: Data([0x10]), isRaw: false, width: 100, height: 100, fileSizeBytes: 1, requestedFormat: .processed, iso: nil, exposureTimeSeconds: nil, fNumber: nil),
            CapturedPhoto(data: Data([0x11]), isRaw: false, width: 100, height: 100, fileSizeBytes: 1, requestedFormat: .processed, iso: nil, exposureTimeSeconds: nil, fNumber: nil),
            CapturedPhoto(data: Data([0x12]), isRaw: false, width: 100, height: 100, fileSizeBytes: 1, requestedFormat: .processed, iso: nil, exposureTimeSeconds: nil, fNumber: nil)
        ])
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.startExposureBracket()

        let done = await waitUntil { mediaStorage.savedDataHistory.count == 3 }
        XCTAssertTrue(done)
    }

    @MainActor
    func testCaptureButtonTappedWithNoTimerCapturesImmediately() async {
        let cameraService = MockCameraService(authorized: true)
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()

        viewModel.captureButtonTapped()

        let didSave = await waitUntil { viewModel.didSavePhoto }
        XCTAssertTrue(didSave)
    }

    @MainActor
    func testSwitchToVideoModeRequestsMicrophoneAndUpdatesConfiguration() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.micAuthorized = true
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        await viewModel.switchToVideoMode()

        XCTAssertEqual(viewModel.configuration.captureMode, .video)
        XCTAssertEqual(cameraService.activeConfiguration.captureMode, .video)
    }

    @MainActor
    func testSwitchToVideoModeWithDeniedMicrophoneStaysInPhotoMode() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.micAuthorized = false
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: MockLibraryStore())
        await viewModel.start()

        await viewModel.switchToVideoMode()

        XCTAssertEqual(viewModel.configuration.captureMode, .photo)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func testStartAndStopRecordingSavesVideo() async {
        let cameraService = MockCameraService(authorized: true)
        let mediaStorage = MockMediaStorage(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage, libraryStore: MockLibraryStore())
        await viewModel.start()
        await viewModel.switchToVideoMode()

        viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)

        viewModel.stopRecording()

        let done = await waitUntil { viewModel.lastRecordedVideo != nil }
        XCTAssertTrue(done)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNotNil(mediaStorage.savedVideoURL)
    }

    @MainActor
    func testCapturePhotoAddsToLocalLibrary() async {
        let cameraService = MockCameraService(authorized: true)
        let libraryStore = MockLibraryStore()
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: libraryStore)
        await viewModel.start()

        viewModel.capturePhoto()

        let done = await waitUntil { libraryStore.addPhotoCallCount == 1 }
        XCTAssertTrue(done)
        XCTAssertEqual(libraryStore.items.first?.kind, .photo)
    }

    @MainActor
    func testStartHDRCaptureSavesFusedResultWithOriginals() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.bracketResult = .success(Self.makeSyntheticBracketFrames())
        let libraryStore = MockLibraryStore()
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: libraryStore)
        await viewModel.start()

        viewModel.startHDRCapture()

        let done = await waitUntil(timeout: 5.0) { viewModel.lastComputationalResult != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(libraryStore.items.first?.kind, .hdrResult)
        XCTAssertEqual(libraryStore.items.first?.originalFileNames.count, 3)
    }

    @MainActor
    func testStartFocusStackSavesStackedResult() async {
        let cameraService = MockCameraService(authorized: true)
        cameraService.focusStackResult = .success(Self.makeSyntheticFocusFrames())
        let libraryStore = MockLibraryStore()
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true), libraryStore: libraryStore)
        await viewModel.start()

        viewModel.startFocusStack()

        let done = await waitUntil(timeout: 5.0) { viewModel.lastComputationalResult != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(libraryStore.items.first?.kind, .focusStackResult)
    }

    private static func makeSyntheticBracketFrames() -> [CapturedPhoto] {
        [
            SyntheticImage.capturedPhoto(color: (0.1, 0.1, 0.1), size: 64),
            SyntheticImage.capturedPhoto(color: (0.5, 0.5, 0.5), size: 64),
            SyntheticImage.capturedPhoto(color: (0.9, 0.9, 0.9), size: 64)
        ]
    }

    private static func makeSyntheticFocusFrames() -> [CapturedPhoto] {
        (0..<3).map { _ in SyntheticImage.capturedPhoto(color: (0.5, 0.5, 0.5), size: 64) }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 1.0, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
