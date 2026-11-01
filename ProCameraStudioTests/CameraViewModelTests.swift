import XCTest
@testable import ProCameraStudio

final class CameraViewModelTests: XCTestCase {

    @MainActor
    func testStartGrantsAuthorizationAndStartsSession() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))

        await viewModel.start()

        XCTAssertEqual(viewModel.authorizationState, .authorized)
        XCTAssertTrue(cameraService.didStartSession)
        XCTAssertTrue(viewModel.isSessionRunning)
    }

    @MainActor
    func testStartWithDeniedAuthorizationDoesNotStartSession() async {
        let cameraService = MockCameraService(authorized: false)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))

        await viewModel.start()

        XCTAssertEqual(viewModel.authorizationState, .denied)
        XCTAssertFalse(cameraService.didStartSession)
    }

    @MainActor
    func testSwitchCameraTogglesPosition() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
        await viewModel.start()

        viewModel.switchCamera()

        XCTAssertEqual(cameraService.activeConfiguration.position, .front)
    }

    @MainActor
    func testSetManualISOUpdatesConfiguration() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
        await viewModel.start()

        viewModel.setManualISO(200)

        XCTAssertEqual(viewModel.configuration.manualISO, 200)
        XCTAssertEqual(cameraService.activeConfiguration.manualISO, 200)
    }

    @MainActor
    func testResetToAutoClearsManualOverrides() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
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
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
        await viewModel.start()
        viewModel.setManualISO(400)

        viewModel.focusAndMeter(at: CGPoint(x: 0.5, y: 0.5))

        XCTAssertNil(viewModel.configuration.manualISO)
        XCTAssertEqual(viewModel.configuration.focusPointOfInterest, CGPoint(x: 0.5, y: 0.5))
    }

    @MainActor
    func testSelectPhotoFormatUpdatesConfiguration() async {
        let cameraService = MockCameraService(authorized: true)
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
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
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: MockMediaStorage(authorized: true))
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
        let viewModel = CameraViewModel(cameraService: cameraService, mediaStorage: mediaStorage)
        await viewModel.start()

        viewModel.capturePhoto()

        let didSave = await waitUntil { viewModel.didSavePhoto }
        XCTAssertTrue(didSave)
        XCTAssertNotNil(mediaStorage.savedData)
        XCTAssertFalse(viewModel.isCapturing)
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
