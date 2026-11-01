import AVFoundation
import Foundation

@MainActor
final class CameraViewModel: ObservableObject {

    enum AuthorizationState: Equatable {
        case unknown
        case authorized
        case denied
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var activeDeviceName = ""
    @Published private(set) var configuration = CaptureConfiguration()
    @Published private(set) var capabilities = CameraCapabilities.fallback
    @Published var errorMessage: String?
    @Published var didSavePhoto = false
    @Published private(set) var lastCapture: CapturedPhotoInfo?

    nonisolated let session: AVCaptureSession
    private let cameraService: CameraServicing
    private let mediaStorage: MediaStoring

    init(cameraService: CameraServicing = CameraService(), mediaStorage: MediaStoring = MediaStorageService()) {
        self.cameraService = cameraService
        self.mediaStorage = mediaStorage
        self.session = cameraService.session
    }

    func start() async {
        guard await cameraService.requestCameraAuthorization() else {
            authorizationState = .denied
            return
        }
        authorizationState = .authorized

        do {
            configuration = try cameraService.configureSession(with: configuration)
            cameraService.startSession()
            isSessionRunning = true
            activeDeviceName = cameraService.activeDeviceName
            capabilities = cameraService.capabilities
        } catch {
            errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() {
        cameraService.stopSession()
        isSessionRunning = false
    }

    // MARK: - Camera/lens selection

    func switchCamera() {
        apply { $0.position = $0.position == .back ? .front : .back }
    }

    func selectLens(_ lens: LensType) {
        apply { $0.lensType = lens }
    }

    func selectPhotoFormat(_ format: PhotoFormat) {
        apply { $0.photoFormat = format }
    }

    // MARK: - Manual controls

    func setManualISO(_ iso: Float?) {
        apply { $0.manualISO = iso }
    }

    func setManualExposureDuration(_ duration: CMTime?) {
        apply { $0.manualExposureDuration = duration }
    }

    func setExposureBias(_ bias: Float?) {
        apply { $0.exposureBias = bias }
    }

    func setManualFocus(_ lensPosition: Float?) {
        apply {
            $0.manualFocusLensPosition = lensPosition
            if lensPosition != nil {
                $0.focusPointOfInterest = nil
                $0.isFocusLocked = false
            }
        }
    }

    func setManualWhiteBalance(_ kelvin: Float?) {
        apply { $0.manualWhiteBalanceKelvin = kelvin }
    }

    func toggleExposureLock() {
        apply {
            $0.isExposureLocked.toggle()
            if $0.isExposureLocked { $0.exposurePointOfInterest = nil }
        }
    }

    func toggleFocusLock() {
        apply {
            $0.isFocusLocked.toggle()
            if $0.isFocusLocked { $0.focusPointOfInterest = nil }
        }
    }

    func resetToAuto() {
        apply {
            $0.manualISO = nil
            $0.manualExposureDuration = nil
            $0.exposureBias = nil
            $0.manualFocusLensPosition = nil
            $0.manualWhiteBalanceKelvin = nil
            $0.focusPointOfInterest = nil
            $0.exposurePointOfInterest = nil
            $0.isExposureLocked = false
            $0.isFocusLocked = false
        }
    }

    /// Called with a device-space point (already converted by CameraPreviewView)
    /// from a tap on the live preview. Tap-to-focus/meter is itself an auto mode,
    /// so it clears any manual overrides and locks.
    func focusAndMeter(at devicePoint: CGPoint) {
        apply {
            $0.focusPointOfInterest = devicePoint
            $0.exposurePointOfInterest = devicePoint
            $0.manualFocusLensPosition = nil
            $0.manualISO = nil
            $0.manualExposureDuration = nil
            $0.isFocusLocked = false
            $0.isExposureLocked = false
        }
    }

    /// Updates local state immediately for a responsive UI, then applies the
    /// change on the camera's session queue. The completion resyncs to whatever
    /// CameraService actually applied, since values may get clamped or a device
    /// swap may reset manual overrides.
    private func apply(_ mutation: (inout CaptureConfiguration) -> Void) {
        var updated = configuration
        mutation(&updated)
        configuration = updated

        cameraService.updateConfiguration(updated) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let normalized):
                self.configuration = normalized
                self.activeDeviceName = self.cameraService.activeDeviceName
                self.capabilities = self.cameraService.capabilities
            case .failure(let error):
                self.errorMessage = error.errorDescription
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        cameraService.capturePhoto { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let captured):
                    let info = CapturedPhotoInfo(from: captured)
                    self.lastCapture = info
                    await self.save(captured.data)
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.lastCapture == info {
                        self.lastCapture = nil
                    }
                case .failure(let error):
                    self.errorMessage = error.errorDescription
                    self.isCapturing = false
                }
            }
        }
    }

    private func save(_ data: Data) async {
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            isCapturing = false
            return
        }
        mediaStorage.savePhotoData(data) { [weak self] result in
            guard let self else { return }
            self.isCapturing = false
            switch result {
            case .success:
                self.didSavePhoto = true
            case .failure(let error):
                self.errorMessage = error.errorDescription
            }
        }
    }
}
