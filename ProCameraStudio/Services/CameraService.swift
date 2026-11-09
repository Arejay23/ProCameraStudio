@preconcurrency import AVFoundation
import CoreImage

final class CameraService: NSObject, CameraServicing {

    let session = AVCaptureSession()

    private(set) var activeConfiguration = CaptureConfiguration()
    private let sessionQueue = DispatchQueue(label: "com.procamerastudio.sessionQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var activeCaptures: [PhotoCaptureProcessor] = []
    private var currentRecordingURL: URL?
    private var videoRecordingProcessor: VideoRecordingProcessor?
    private var interruptionObserver: NSObjectProtocol?

    // Histogram (Phase 8): throttled so a continuous analysis tap doesn't add
    // meaningful preview-stability risk — this is the pipeline Phase 2
    // deferred building until there was a concrete, scoped use for it.
    private var histogramUpdateHandler: ((HistogramData) -> Void)?
    private var histogramFrameCounter = 0
    private let histogramFrameInterval = 6
    private let analysisQueue = DispatchQueue(label: "com.procamerastudio.analysisQueue", qos: .utility)

    private static let minimumFreeBytesToStartRecording: Int64 = 200 * 1024 * 1024

    override init() {
        super.init()
        observeInterruptions()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    var activeDeviceName: String {
        videoDeviceInput?.device.localizedName ?? "No Camera"
    }

    var isRecording: Bool {
        movieFileOutput.isRecording
    }

    var currentRecordingFileSizeBytes: Int {
        guard let url = currentRecordingURL else { return 0 }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    var videoCapabilities: VideoCapabilities {
        guard let device = videoDeviceInput?.device else { return .fallback }
        let availableResolutions = VideoResolution.allCases.filter { session.canSetSessionPreset($0.sessionPreset) }
        let candidateFrameRates: [Double] = [24, 30, 60]
        let availableFrameRates = candidateFrameRates.filter { rate in
            device.activeFormat.videoSupportedFrameRateRanges.contains { rate >= $0.minFrameRate && rate <= $0.maxFrameRate }
        }
        return VideoCapabilities(
            availableResolutions: availableResolutions,
            availableFrameRates: availableFrameRates.isEmpty ? [30] : availableFrameRates,
            supportsProRes: movieFileOutput.availableVideoCodecTypes.contains(.proRes422)
        )
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

    func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
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
                guard !self.movieFileOutput.isRecording else {
                    throw CameraError.configurationFailed("Can't change settings while recording.")
                }

                let needsDeviceSwap = configuration.position != self.activeConfiguration.position
                    || configuration.lensType != self.activeConfiguration.lensType
                let needsVideoReconfig = configuration.captureMode == .video && (
                    self.activeConfiguration.captureMode != .video
                    || configuration.videoResolution != self.activeConfiguration.videoResolution
                    || configuration.videoFrameRate != self.activeConfiguration.videoFrameRate
                )
                let needsPhotoReconfig = configuration.captureMode == .photo && self.activeConfiguration.captureMode != .photo

                if needsVideoReconfig {
                    try self.configureVideoMode(resolution: configuration.videoResolution, frameRate: configuration.videoFrameRate)
                    self.activeConfiguration.captureMode = .video
                } else if needsPhotoReconfig {
                    try self.configurePhotoMode()
                    self.activeConfiguration.captureMode = .photo
                }

                if needsDeviceSwap {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    try self.setVideoInput(for: configuration.position, lensType: configuration.lensType)
                    // photoOutput is already connected (added once, in configureSession)
                    // so this is safe here, unlike the first-ever setup.
                    if self.activeConfiguration.captureMode == .photo {
                        self.updateMaxPhotoDimensions()
                    }
                }

                guard let device = self.videoDeviceInput?.device else {
                    throw CameraError.deviceUnavailable
                }
                var requested = configuration
                requested.position = self.activeConfiguration.position
                requested.lensType = self.activeConfiguration.lensType
                requested.captureMode = self.activeConfiguration.captureMode
                requested.videoResolution = self.activeConfiguration.videoResolution
                requested.videoFrameRate = self.activeConfiguration.videoFrameRate
                var applied = try self.applyManualSettings(requested, to: device)
                self.validatePhotoFormat(&applied)
                self.validateVideoSettings(&applied)
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
            guard self.session.outputs.contains(self.photoOutput) else {
                DispatchQueue.main.async { completion(.failure(.captureFailed("Switch to photo mode before capturing a photo."))) }
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

    // MARK: - Photo/video mode (Phase 5)

    private func configurePhotoMode() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.outputs.contains(movieFileOutput) {
            session.removeOutput(movieFileOutput)
        }
        if let audioDeviceInput {
            session.removeInput(audioDeviceInput)
            self.audioDeviceInput = nil
        }
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        updateMaxPhotoDimensions()
        if histogramUpdateHandler != nil {
            addVideoDataOutputIfNeeded()
        }
    }

    private func configureVideoMode(resolution: VideoResolution, frameRate: Double) throws {
        session.beginConfiguration()
        do {
            if session.outputs.contains(photoOutput) {
                session.removeOutput(photoOutput)
            }
            if session.outputs.contains(videoDataOutput) {
                session.removeOutput(videoDataOutput)
            }
            if audioDeviceInput == nil, let audioDevice = AVCaptureDevice.default(for: .audio) {
                let input = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                    audioDeviceInput = input
                }
            }
            let preset = resolution.sessionPreset
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
            }
            if !session.outputs.contains(movieFileOutput), session.canAddOutput(movieFileOutput) {
                session.addOutput(movieFileOutput)
            }
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()

        try applyFrameRate(frameRate)
        activeConfiguration.videoResolution = resolution
        activeConfiguration.videoFrameRate = frameRate
    }

    private func applyFrameRate(_ frameRate: Double) throws {
        guard let device = videoDeviceInput?.device else { return }
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            frameRate >= $0.minFrameRate && frameRate <= $0.maxFrameRate
        }
        guard supported else {
            throw CameraError.configurationFailed("This camera doesn't support \(Int(frameRate)) fps at the selected resolution.")
        }
        try device.lockForConfiguration()
        let duration = CMTimeMake(value: 1, timescale: Int32(frameRate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    /// Resets ProRes/resolution to something actually supported if the
    /// requested combination isn't — same honesty discipline as validatePhotoFormat.
    private func validateVideoSettings(_ configuration: inout CaptureConfiguration) {
        guard configuration.captureMode == .video else { return }
        if configuration.useProResVideo, !movieFileOutput.availableVideoCodecTypes.contains(.proRes422) {
            configuration.useProResVideo = false
        }
        let caps = videoCapabilities
        if !caps.availableResolutions.contains(configuration.videoResolution), let first = caps.availableResolutions.first {
            configuration.videoResolution = first
        }
    }

    // MARK: - Recording (Phase 5)

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self, self.movieFileOutput.isRecording else { return }
            self.movieFileOutput.stopRecording()
        }
    }

    func startRecording() throws {
        guard !movieFileOutput.isRecording else {
            throw CameraError.captureFailed("Already recording.")
        }
        guard activeConfiguration.captureMode == .video, session.outputs.contains(movieFileOutput) else {
            throw CameraError.captureFailed("Switch to video mode before recording.")
        }
        guard Self.availableDiskCapacityBytes() > Self.minimumFreeBytesToStartRecording else {
            throw CameraError.captureFailed("Not enough free storage to start recording.")
        }
        guard ProcessInfo.processInfo.thermalState != .critical else {
            throw CameraError.captureFailed("Device is too hot to record right now. Let it cool down and try again.")
        }

        let useProRes = activeConfiguration.useProResVideo && movieFileOutput.availableVideoCodecTypes.contains(.proRes422)
        if let connection = movieFileOutput.connection(with: .video) {
            let codec: AVVideoCodecType = useProRes ? .proRes422 : .hevc
            if movieFileOutput.availableVideoCodecTypes.contains(codec) {
                movieFileOutput.setOutputSettings([AVVideoCodecKey: codec], for: connection)
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        currentRecordingURL = tempURL

        let processor = VideoRecordingProcessor(resolution: activeConfiguration.videoResolution, usedProRes: useProRes)
        videoRecordingProcessor = processor
        movieFileOutput.startRecording(to: tempURL, recordingDelegate: processor)
    }

    func stopRecording(completion: @escaping (Result<RecordedVideo, CameraError>) -> Void) {
        guard movieFileOutput.isRecording else {
            completion(.failure(.captureFailed("Not currently recording.")))
            return
        }
        videoRecordingProcessor?.completion = { [weak self] result in
            self?.currentRecordingURL = nil
            self?.videoRecordingProcessor = nil
            DispatchQueue.main.async { completion(result) }
        }
        movieFileOutput.stopRecording()
    }

    private static func availableDiskCapacityBytes() -> Int64 {
        guard let url = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return .max
        }
        return capacity
    }

    // MARK: - Histogram (Phase 8)

    func setHistogramEnabled(_ enabled: Bool, update: @escaping (HistogramData) -> Void) {
        histogramUpdateHandler = enabled ? update : nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.activeConfiguration.captureMode == .photo else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if enabled {
                self.addVideoDataOutputIfNeeded()
            } else if self.session.outputs.contains(self.videoDataOutput) {
                self.session.removeOutput(self.videoDataOutput)
            }
        }
    }

    /// Assumes it's called inside an already-open session configuration
    /// transaction (either this method's own, or configurePhotoMode's) —
    /// AVCaptureSession doesn't officially support nested begin/commit pairs,
    /// so this never opens one of its own.
    private func addVideoDataOutputIfNeeded() {
        guard !session.outputs.contains(videoDataOutput) else { return }
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
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
        // Callers must set maxPhotoDimensions themselves, after photoOutput is
        // actually connected — on the very first setup (configureSession) that
        // output doesn't exist yet, and AVCapturePhotoOutput throws if you set
        // maxPhotoDimensions before it has a connected device with an activeFormat.
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

    // MARK: - Multi-frame capture (Phase 4)

    func captureMultiFrameBurst(settings: MultiFrameCaptureSettings, progress: @escaping (Int, Int) -> Void) async throws -> MultiFrameCaptureResult {
        let stacker = FrameStacker(algorithm: settings.algorithm)
        var originals: [CapturedPhoto] = []

        for index in 0..<max(settings.frameCount, 1) {
            try Task.checkCancellation()
            let captured = try await captureSingleFrameForStacking()
            stacker.add(captured)
            if settings.saveOriginalFrames {
                originals.append(captured)
            }
            progress(index + 1, settings.frameCount)

            if index < settings.frameCount - 1 {
                try await Task.sleep(nanoseconds: UInt64(max(settings.intervalSeconds, 0) * 1_000_000_000))
            }
        }

        guard let stacked = stacker.finish() else {
            throw CameraError.captureFailed("No frames were captured.")
        }
        return MultiFrameCaptureResult(stacked: stacked, originalFrames: originals)
    }

    func captureExposureBracket(settings: BracketSettings, progress: @escaping (Int, Int) -> Void) async throws -> [CapturedPhoto] {
        guard let device = videoDeviceInput?.device else { throw CameraError.deviceUnavailable }
        let centerBias = activeConfiguration.exposureBias ?? 0
        let offsets = Self.bracketOffsets(count: settings.frameCount, stepEV: settings.exposureStepEV)
        var frames: [CapturedPhoto] = []

        for (index, offset) in offsets.enumerated() {
            try Task.checkCancellation()
            let bias = clamp(centerBias + offset, device.minExposureTargetBias, device.maxExposureTargetBias)
            try await setExposureBiasOnly(bias, device: device)
            let captured = try await captureSingleFrameForStacking()
            frames.append(captured)
            progress(index + 1, offsets.count)
        }

        try? await setExposureBiasOnly(centerBias, device: device)
        return frames
    }

    private static func bracketOffsets(count: Int, stepEV: Float) -> [Float] {
        guard count > 1 else { return [0] }
        let half = Float(count - 1) / 2
        return (0..<count).map { (Float($0) - half) * stepEV }
    }

    /// Sets exposure bias and waits for AVFoundation's own completion handler,
    /// which fires once the new bias has actually taken effect on a frame —
    /// important for bracketing, where capturing too early would reuse the
    /// previous frame's exposure.
    private func setExposureBiasOnly(_ bias: Float, device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()
                } catch {
                    continuation.resume(throwing: CameraError.configurationFailed("Camera is busy: \(error.localizedDescription)"))
                    return
                }
                device.setExposureTargetBias(bias) { _ in
                    continuation.resume()
                }
                device.unlockForConfiguration()
            }
        }
    }

    func captureFocusStack(settings: FocusStackSettings, progress: @escaping (Int, Int) -> Void) async throws -> [CapturedPhoto] {
        guard let device = videoDeviceInput?.device, device.isFocusModeSupported(.locked) else {
            throw CameraError.captureFailed("Manual focus isn't supported by this camera/lens.")
        }
        let positions = Self.focusPositions(count: settings.frameCount)
        var frames: [CapturedPhoto] = []

        for (index, position) in positions.enumerated() {
            try Task.checkCancellation()
            try await setFocusPositionOnly(position, device: device)
            let captured = try await captureSingleFrameForStacking()
            frames.append(captured)
            progress(index + 1, positions.count)
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            try? await setFocusPositionOnly(nil, device: device)
        }
        return frames
    }

    private static func focusPositions(count: Int) -> [Float] {
        guard count > 1 else { return [0.5] }
        return (0..<count).map { Float($0) / Float(count - 1) }
    }

    /// Sets manual focus lens position and waits for AVFoundation's own
    /// completion handler, same reasoning as setExposureBiasOnly. Passing nil
    /// restores continuous autofocus instead of locking to a position.
    private func setFocusPositionOnly(_ position: Float?, device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()
                } catch {
                    continuation.resume(throwing: CameraError.configurationFailed("Camera is busy: \(error.localizedDescription)"))
                    return
                }
                if let position {
                    device.setFocusModeLocked(lensPosition: position) { _ in
                        continuation.resume()
                    }
                } else {
                    device.focusMode = .continuousAutoFocus
                    continuation.resume()
                }
                device.unlockForConfiguration()
            }
        }
    }

    /// Single-frame capture used by burst/bracket sequences: always .processed
    /// (RAW bursts would be impractically large), favoring speed over quality
    /// since consistency across frames matters more than any one frame here.
    private func captureSingleFrameForStacking() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CapturedPhoto, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.captureFailed("Camera unavailable"))
                    return
                }
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.captureFailed("Camera session is not running"))
                    return
                }
                guard self.session.outputs.contains(self.photoOutput) else {
                    continuation.resume(throwing: CameraError.captureFailed("Switch to photo mode first."))
                    return
                }

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .speed
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions

                var processor: PhotoCaptureProcessor!
                processor = PhotoCaptureProcessor(requestedFormat: .processed) { [weak self] result in
                    self?.sessionQueue.async {
                        self?.activeCaptures.removeAll { $0 === processor }
                    }
                    switch result {
                    case .success(let photo):
                        continuation.resume(returning: photo)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                self.activeCaptures.append(processor)
                self.photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }
}

private func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        histogramFrameCounter += 1
        guard histogramFrameCounter % histogramFrameInterval == 0 else { return }
        guard let handler = histogramUpdateHandler else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let histogramData = Self.computeHistogram(from: ciImage) else { return }
        DispatchQueue.main.async { handler(histogramData) }
    }

    /// CIAreaHistogram is the Core Image filter designed exactly for this —
    /// it computes the histogram on the GPU, and only a tiny (binCount x 1)
    /// image needs to be rendered out, not the full camera frame, keeping
    /// this cheap even running continuously on a background queue.
    private static func computeHistogram(from image: CIImage) -> HistogramData? {
        let binCount = 64
        guard let histogramFilter = CIFilter(name: "CIAreaHistogram") else { return nil }
        histogramFilter.setValue(image, forKey: kCIInputImageKey)
        histogramFilter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        histogramFilter.setValue(binCount, forKey: "inputCount")
        histogramFilter.setValue(1.0, forKey: "inputScale")
        guard let histogramImage = histogramFilter.outputImage else { return nil }

        let context = CIContext()
        var bitmap = [Float](repeating: 0, count: binCount * 4)
        context.render(
            histogramImage,
            toBitmap: &bitmap,
            rowBytes: binCount * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )

        var red = [Float](repeating: 0, count: binCount)
        var green = [Float](repeating: 0, count: binCount)
        var blue = [Float](repeating: 0, count: binCount)
        var maxValue: Float = 0.0001
        for i in 0..<binCount {
            red[i] = bitmap[i * 4]
            green[i] = bitmap[i * 4 + 1]
            blue[i] = bitmap[i * 4 + 2]
            maxValue = max(maxValue, red[i], green[i], blue[i])
        }
        for i in 0..<binCount {
            red[i] /= maxValue
            green[i] /= maxValue
            blue[i] /= maxValue
        }
        return HistogramData(red: red, green: green, blue: blue)
    }
}
