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
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var errorMessage: String?
    @Published var didSavePhoto = false

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
            try cameraService.configureSession(with: CaptureConfiguration(position: position))
            cameraService.startSession()
            isSessionRunning = true
            activeDeviceName = cameraService.activeDeviceName
        } catch {
            errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() {
        cameraService.stopSession()
        isSessionRunning = false
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        do {
            try cameraService.updateConfiguration(CaptureConfiguration(position: newPosition))
            position = newPosition
            activeDeviceName = cameraService.activeDeviceName
        } catch {
            errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        cameraService.capturePhoto { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let data):
                    await self.save(data)
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
