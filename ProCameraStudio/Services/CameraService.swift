import AVFoundation

final class CameraService: NSObject, CameraServicing {

    let session = AVCaptureSession()

    private(set) var activeConfiguration = CaptureConfiguration()
    private let sessionQueue = DispatchQueue(label: "com.procamerastudio.sessionQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var activeCaptures: [PhotoCaptureProcessor] = []

    var activeDeviceName: String {
        videoDeviceInput?.device.localizedName ?? "No Camera"
    }

    func requestCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func configureSession(with configuration: CaptureConfiguration) throws {
        try sessionQueue.sync {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .photo
            try setVideoInput(for: configuration.position)

            guard session.canAddOutput(photoOutput) else {
                throw CameraError.configurationFailed("Unable to add photo output")
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality

            activeConfiguration = configuration
        }
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) throws {
        guard configuration.position != activeConfiguration.position else { return }
        try sessionQueue.sync {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            try setVideoInput(for: configuration.position)
            activeConfiguration = configuration
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard self.session.isRunning else {
                DispatchQueue.main.async { completion(.failure(.captureFailed("Camera session is not running"))) }
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality

            var processor: PhotoCaptureProcessor!
            processor = PhotoCaptureProcessor { [weak self] result in
                self?.sessionQueue.async {
                    self?.activeCaptures.removeAll { $0 === processor }
                }
                DispatchQueue.main.async { completion(result) }
            }
            self.activeCaptures.append(processor)
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: - Device discovery

    private func setVideoInput(for position: AVCaptureDevice.Position) throws {
        guard let device = Self.discoverDevice(for: position) else {
            throw CameraError.deviceUnavailable
        }

        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
            videoDeviceInput = nil
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("Unable to add input for \(device.localizedName)")
        }
        session.addInput(input)
        videoDeviceInput = input
    }

    /// Picks the richest camera system available for the position (e.g. the triple
    /// camera on iPhone 14 Pro's back), satisfying runtime capability detection.
    private static func discoverDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }
}
