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

    var capabilities: CameraCapabilities {
        guard let device = videoDeviceInput?.device else { return .fallback }
        let format = device.activeFormat
        return CameraCapabilities(
            minISO: format.minISO,
            maxISO: format.maxISO,
            minExposureDurationSeconds: CMTimeGetSeconds(format.minExposureDuration),
            maxExposureDurationSeconds: CMTimeGetSeconds(format.maxExposureDuration),
            minExposureTargetBias: device.minExposureTargetBias,
            maxExposureTargetBias: device.maxExposureTargetBias,
            minWhiteBalanceKelvin: 2000,
            maxWhiteBalanceKelvin: 10000,
            supportsManualFocus: device.isFocusModeSupported(.locked),
            availableLenses: Self.availableLenses(for: activeConfiguration.position),
            supportsRAW: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            supportsAppleProRAW: photoOutput.isAppleProRAWSupported
        )
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

    func configureSession(with configuration: CaptureConfiguration) throws -> CaptureConfiguration {
        try sessionQueue.sync {
            session.beginConfiguration()
            do {
                session.sessionPreset = .photo
                try setVideoInput(for: configuration.position, lensType: configuration.lensType)

                guard session.canAddOutput(photoOutput) else {
                    throw CameraError.configurationFailed("Unable to add photo output")
                }
                session.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .quality
                updateMaxPhotoDimensions()
            } catch {
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()

            guard let device = videoDeviceInput?.device else {
                throw CameraError.deviceUnavailable
            }
            var requested = configuration
            requested.position = activeConfiguration.position
            requested.lensType = activeConfiguration.lensType
            var applied = try applyManualSettings(requested, to: device)
            validatePhotoFormat(&applied)
            activeConfiguration = applied
            return activeConfiguration
        }
    }

    func updateConfiguration(_ configuration: CaptureConfiguration, completion: @escaping (Result<CaptureConfiguration, CameraError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let needsDeviceSwap = configuration.position != self.activeConfiguration.position
                    || configuration.lensType != self.activeConfiguration.lensType

                if needsDeviceSwap {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    try self.setVideoInput(for: configuration.position, lensType: configuration.lensType)
                }

                guard let device = self.videoDeviceInput?.device else {
                    throw CameraError.deviceUnavailable
                }
                var requested = configuration
                requested.position = self.activeConfiguration.position
                requested.lensType = self.activeConfiguration.lensType
                var applied = try self.applyManualSettings(requested, to: device)
                self.validatePhotoFormat(&applied)
                self.activeConfiguration = applied

                let result = self.activeConfiguration
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                let cameraError = (error as? CameraError) ?? CameraError.configurationFailed(error.localizedDescription)
                DispatchQueue.main.async { completion(.failure(cameraError)) }
            }
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

    func capturePhoto(completion: @escaping (Result<CapturedPhoto, CameraError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard self.session.isRunning else {
                DispatchQueue.main.async { completion(.failure(.captureFailed("Camera session is not running"))) }
                return
            }

            let format = self.activeConfiguration.photoFormat
            let settings: AVCapturePhotoSettings
            do {
                settings = try self.makePhotoSettings(for: format)
            } catch {
                self.photoOutput.isAppleProRAWEnabled = false
                let cameraError = (error as? CameraError) ?? CameraError.captureFailed(error.localizedDescription)
                DispatchQueue.main.async { completion(.failure(cameraError)) }
                return
            }

            var processor: PhotoCaptureProcessor!
            processor = PhotoCaptureProcessor(requestedFormat: format) { [weak self] result in
                self?.sessionQueue.async {
                    self?.activeCaptures.removeAll { $0 === processor }
                    // Resting state is always "off" so capability checks (and the
                    // next capture's settings) never see a stale enabled flag.
                    self?.photoOutput.isAppleProRAWEnabled = false
                }
                DispatchQueue.main.async { completion(result) }
            }
            self.activeCaptures.append(processor)
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    /// Builds settings for the requested format, enabling Apple ProRAW on the
    /// output only for the duration of this capture. Throws rather than
    /// silently downgrading to .processed, so the caller can report a real
    /// failure instead of a capture that doesn't match what was requested.
    private func makePhotoSettings(for format: PhotoFormat) throws -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        switch format {
        case .processed:
            photoOutput.isAppleProRAWEnabled = false
            settings = AVCapturePhotoSettings()
        case .raw:
            photoOutput.isAppleProRAWEnabled = false
            guard let rawType = Self.rawPixelFormat(wantsProRAW: false, output: photoOutput) else {
                throw CameraError.captureFailed("Standard RAW capture isn't supported by this camera/lens.")
            }
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
        case .appleProRAW:
            guard photoOutput.isAppleProRAWSupported else {
                throw CameraError.captureFailed("Apple ProRAW isn't supported by this camera/lens.")
            }
            photoOutput.isAppleProRAWEnabled = true
            guard let rawType = Self.rawPixelFormat(wantsProRAW: true, output: photoOutput) else {
                throw CameraError.captureFailed("Apple ProRAW isn't available right now.")
            }
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
        }
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        return settings
    }

    private static func rawPixelFormat(wantsProRAW: Bool, output: AVCapturePhotoOutput) -> OSType? {
        let predicate: (OSType) -> Bool = wantsProRAW
            ? AVCapturePhotoOutput.isAppleProRAWPixelFormat
            : AVCapturePhotoOutput.isBayerRAWPixelFormat
        return output.availableRawPhotoPixelFormatTypes.first(where: predicate)
    }

    /// Resets to .processed if the requested format isn't actually supported,
    /// e.g. after switching to a lens/position without RAW support.
    private func validatePhotoFormat(_ configuration: inout CaptureConfiguration) {
        switch configuration.photoFormat {
        case .processed:
            return
        case .raw:
            if photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                configuration.photoFormat = .processed
            }
        case .appleProRAW:
            if !photoOutput.isAppleProRAWSupported {
                configuration.photoFormat = .processed
            }
        }
    }

    private func updateMaxPhotoDimensions() {
        guard let device = videoDeviceInput?.device else { return }
        if let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            photoOutput.maxPhotoDimensions = maxDimensions
        }
    }

    // MARK: - Device selection

    private func setVideoInput(for position: AVCaptureDevice.Position, lensType: LensType) throws {
        let resolvedLens = Self.resolveLensType(lensType, for: position)
        guard let device = AVCaptureDevice.default(resolvedLens.deviceType, for: .video, position: position) else {
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
        activeConfiguration.position = position
        activeConfiguration.lensType = resolvedLens
        updateMaxPhotoDimensions()
    }

    /// iPhone 14 Pro's front camera has no ultra-wide/telephoto; fall back to wide.
    private static func resolveLensType(_ lensType: LensType, for position: AVCaptureDevice.Position) -> LensType {
        guard position == .back else { return .wide }
        return lensType
    }

    private static func availableLenses(for position: AVCaptureDevice.Position) -> [LensType] {
        guard position == .back else { return [.wide] }
        return LensType.allCases.filter { AVCaptureDevice.default($0.deviceType, for: .video, position: position) != nil }
    }

    // MARK: - Manual controls

    /// Locks the device, applies exposure/focus/white-balance, and returns the
    /// configuration with every manual value clamped (or cleared, if the mode
    /// isn't supported) to what was actually applied to the hardware.
    @discardableResult
    private func applyManualSettings(_ configuration: CaptureConfiguration, to device: AVCaptureDevice) throws -> CaptureConfiguration {
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError.configurationFailed("Camera is busy: \(error.localizedDescription)")
        }
        defer { device.unlockForConfiguration() }

        var applied = configuration
        applyExposure(&applied, to: device)
        applyFocus(&applied, to: device)
        applyWhiteBalance(&applied, to: device)
        return applied
    }

    private func applyExposure(_ configuration: inout CaptureConfiguration, to device: AVCaptureDevice) {
        if configuration.isManualExposureEnabled, device.isExposureModeSupported(.custom) {
            let clampedISO = configuration.manualISO.map {
                clamp($0, device.activeFormat.minISO, device.activeFormat.maxISO)
            }
            let duration = configuration.manualExposureDuration ?? AVCaptureDevice.currentExposureDuration
            let iso = clampedISO ?? AVCaptureDevice.currentISO
            device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            configuration.manualISO = clampedISO
        } else {
            if configuration.isManualExposureEnabled {
                // Custom exposure isn't supported on this device/format — fall back
                // honestly rather than claiming a manual value is active.
                configuration.manualISO = nil
                configuration.manualExposureDuration = nil
            }
            if let point = configuration.exposurePointOfInterest,
               device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            } else if configuration.isExposureLocked, device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }

        let clampedBias = configuration.exposureBias.map {
            clamp($0, device.minExposureTargetBias, device.maxExposureTargetBias)
        }
        device.setExposureTargetBias(clampedBias ?? 0, completionHandler: nil)
        configuration.exposureBias = clampedBias
    }

    private func applyFocus(_ configuration: inout CaptureConfiguration, to device: AVCaptureDevice) {
        if let lensPosition = configuration.manualFocusLensPosition, device.isFocusModeSupported(.locked) {
            let clamped = clamp(lensPosition, 0, 1)
            device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
            configuration.manualFocusLensPosition = clamped
        } else {
            if configuration.manualFocusLensPosition != nil {
                configuration.manualFocusLensPosition = nil
            }
            if let point = configuration.focusPointOfInterest,
               device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            } else if configuration.isFocusLocked, device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }
    }

    private func applyWhiteBalance(_ configuration: inout CaptureConfiguration, to device: AVCaptureDevice) {
        if let kelvin = configuration.manualWhiteBalanceKelvin, device.isWhiteBalanceModeSupported(.locked) {
            let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: 0)
            var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
            gains.redGain = clamp(gains.redGain, 1, device.maxWhiteBalanceGain)
            gains.greenGain = clamp(gains.greenGain, 1, device.maxWhiteBalanceGain)
            gains.blueGain = clamp(gains.blueGain, 1, device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        } else {
            if configuration.manualWhiteBalanceKelvin != nil {
                configuration.manualWhiteBalanceKelvin = nil
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }
}

private func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
