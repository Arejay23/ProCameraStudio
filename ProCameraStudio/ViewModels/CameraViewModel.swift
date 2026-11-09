import AVFoundation
import Combine
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

    // Phase 4: timed/sequence capture. These are transient workflow state, not
    // continuous device settings, so they live here rather than in
    // CaptureConfiguration/CameraServicing.
    @Published var countdownDuration = 0
    @Published private(set) var countdownSeconds: Int?
    @Published private(set) var isIntervalCaptureRunning = false
    @Published private(set) var multiFrameProgress: (current: Int, total: Int)?
    @Published private(set) var lastMultiFrameCapture: CapturedPhotoInfo?
    @Published private(set) var bracketProgress: (current: Int, total: Int)?
    @Published private(set) var isDeviceStable = true

    // Phase 5: video recording.
    @Published private(set) var videoCapabilities = VideoCapabilities.fallback
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var recordingFileSizeBytes = 0
    @Published private(set) var lastRecordedVideo: RecordedVideoInfo?

    // Phase 6: computational photography (HDR fusion, focus stacking). Shares
    // one progress/result pair since only one can run at a time.
    @Published private(set) var computationalProgress: (current: Int, total: Int)?
    @Published private(set) var lastComputationalResult: CapturedPhotoInfo?

    nonisolated let session: AVCaptureSession
    private let cameraService: CameraServicing
    private let mediaStorage: MediaStoring
    private let libraryStore: LibraryStoring
    private let motionMonitor = MotionMonitor()
    private var cancellables = Set<AnyCancellable>()

    private var countdownTask: Task<Void, Never>?
    private var intervalTask: Task<Void, Never>?
    private var multiFrameTask: Task<Void, Never>?
    private var bracketTask: Task<Void, Never>?
    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartDate: Date?
    private var hdrTask: Task<Void, Never>?
    private var focusStackTask: Task<Void, Never>?

    // No default for libraryStore: it's @MainActor-isolated, and Swift
    // evaluates default-argument expressions in a nonisolated context, so
    // `= LibraryStore()` here is a hard compile error. Every call site
    // (ContentView, tests) passes it explicitly instead.
    init(
        cameraService: CameraServicing = CameraService(),
        mediaStorage: MediaStoring = MediaStorageService(),
        libraryStore: LibraryStoring
    ) {
        self.cameraService = cameraService
        self.mediaStorage = mediaStorage
        self.libraryStore = libraryStore
        self.session = cameraService.session
        motionMonitor.$isStable
            .assign(to: \.isDeviceStable, on: self)
            .store(in: &cancellables)
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
            videoCapabilities = cameraService.videoCapabilities
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

    // MARK: - Photo/video mode (Phase 5)

    func switchToVideoMode() async {
        guard await cameraService.requestMicrophoneAuthorization() else {
            errorMessage = "Microphone access is required to record video. Enable it in Settings."
            return
        }
        apply { $0.captureMode = .video }
    }

    func switchToPhotoMode() {
        guard !isRecording else { return }
        apply { $0.captureMode = .photo }
    }

    func selectVideoResolution(_ resolution: VideoResolution) {
        guard !isRecording else { return }
        apply { $0.videoResolution = resolution }
    }

    func selectVideoFrameRate(_ frameRate: Double) {
        guard !isRecording else { return }
        apply { $0.videoFrameRate = frameRate }
    }

    func toggleProResVideo(_ enabled: Bool) {
        guard !isRecording else { return }
        apply { $0.useProResVideo = enabled }
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
                self.videoCapabilities = self.cameraService.videoCapabilities
            case .failure(let error):
                self.errorMessage = error.errorDescription
            }
        }
    }

    // MARK: - Capture

    /// What the shutter button actually does: cancels an in-flight countdown,
    /// starts one if a timer duration is selected, or captures immediately.
    func captureButtonTapped() {
        if countdownSeconds != nil {
            cancelCountdown()
        } else if countdownDuration > 0 {
            startCountdown(seconds: countdownDuration)
        } else {
            capturePhoto()
        }
    }

    func startCountdown(seconds: Int) {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self.countdownSeconds = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled {
                    self.countdownSeconds = nil
                    return
                }
            }
            self.countdownSeconds = nil
            self.capturePhoto()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownSeconds = nil
    }

    func startIntervalCapture(every seconds: Double) {
        guard !isIntervalCaptureRunning else { return }
        isIntervalCaptureRunning = true
        intervalTask = Task { @MainActor in
            while !Task.isCancelled {
                self.capturePhoto()
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 1) * 1_000_000_000))
            }
        }
    }

    func stopIntervalCapture() {
        intervalTask?.cancel()
        intervalTask = nil
        isIntervalCaptureRunning = false
    }

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
                    await self.save(captured)
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

    private func save(_ captured: CapturedPhoto) async {
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            isCapturing = false
            return
        }
        let result = await saveAsync(captured.data)
        isCapturing = false
        switch result {
        case .success:
            didSavePhoto = true
            addToLibrary(captured)
        case .failure(let error):
            errorMessage = error.errorDescription
        }
    }

    private func saveAsync(_ data: Data) async -> Result<Void, CameraError> {
        await withCheckedContinuation { continuation in
            mediaStorage.savePhotoData(data) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Adds a captured photo to the app's local library (Phase 7) — never the
    /// Photos library, which already got its own copy via mediaStorage.
    private func addToLibrary(_ captured: CapturedPhoto, originals: [CapturedPhoto] = [], kindOverride: LibraryItemKind? = nil) {
        let info = CapturedPhotoInfo(from: captured)
        let kind = kindOverride ?? (captured.isRaw ? .rawPhoto : .photo)
        libraryStore.addPhoto(
            data: captured.data,
            kind: kind,
            width: captured.width,
            height: captured.height,
            formatLabel: info.formatLabel,
            iso: captured.iso,
            exposureTimeSeconds: captured.exposureTimeSeconds,
            fNumber: captured.fNumber,
            originals: originals.map { $0.data }
        )
    }

    // MARK: - Multi-frame capture (Phase 4)

    func startMultiFrameCapture(mode: NightCaptureMode, saveOriginalFrames: Bool = false) {
        guard multiFrameTask == nil else { return }
        if ProcessInfo.processInfo.thermalState == .critical {
            errorMessage = "Device is too hot for multi-frame capture right now. Let it cool down and try again."
            return
        }

        let settings = MultiFrameCaptureSettings(
            frameCount: mode.defaultFrameCount,
            intervalSeconds: mode.defaultIntervalSeconds,
            algorithm: mode.algorithm,
            saveOriginalFrames: saveOriginalFrames
        )
        multiFrameProgress = (0, settings.frameCount)
        motionMonitor.start()

        multiFrameTask = Task { @MainActor in
            do {
                let result = try await cameraService.captureMultiFrameBurst(settings: settings) { current, total in
                    Task { @MainActor in
                        self.multiFrameProgress = (current, total)
                    }
                }
                await handleMultiFrameResult(result)
            } catch is CancellationError {
                // User-cancelled; nothing to report.
            } catch {
                errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
            }
            motionMonitor.stop()
            multiFrameProgress = nil
            multiFrameTask = nil
        }
    }

    func cancelMultiFrameCapture() {
        multiFrameTask?.cancel()
    }

    private func handleMultiFrameResult(_ result: MultiFrameCaptureResult) async {
        let info = CapturedPhotoInfo(from: result.stacked)
        lastMultiFrameCapture = info
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            return
        }
        if case .failure(let error) = await saveAsync(result.stacked.data) {
            errorMessage = error.errorDescription
        } else {
            addToLibrary(result.stacked, originals: result.originalFrames, kindOverride: .nightStackResult)
        }
        for frame in result.originalFrames {
            _ = await saveAsync(frame.data)
        }
    }

    // MARK: - Exposure bracketing (Phase 4)

    func startExposureBracket(frameCount: Int = 3, stepEV: Float = 1.0) {
        guard bracketTask == nil else { return }
        let settings = BracketSettings(frameCount: frameCount, exposureStepEV: stepEV)
        bracketProgress = (0, frameCount)

        bracketTask = Task { @MainActor in
            do {
                let frames = try await cameraService.captureExposureBracket(settings: settings) { current, total in
                    Task { @MainActor in
                        self.bracketProgress = (current, total)
                    }
                }
                await saveBracketFrames(frames)
            } catch is CancellationError {
                // User-cancelled; nothing to report.
            } catch {
                errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
            }
            bracketProgress = nil
            bracketTask = nil
        }
    }

    func cancelExposureBracket() {
        bracketTask?.cancel()
    }

    private func saveBracketFrames(_ frames: [CapturedPhoto]) async {
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            return
        }
        for frame in frames {
            if case .success = await saveAsync(frame.data) {
                addToLibrary(frame)
            }
        }
        if let last = frames.last {
            lastCapture = CapturedPhotoInfo(from: last)
        }
    }

    /// Call when the camera screen disappears, to stop any in-flight Phase 4
    /// workflow cleanly rather than leaving it running against a torn-down session.
    func cancelAllSequenceCapture() {
        cancelCountdown()
        stopIntervalCapture()
        cancelMultiFrameCapture()
        cancelExposureBracket()
        cancelHDRCapture()
        cancelFocusStack()
        if isRecording {
            stopRecording()
        }
    }

    // MARK: - Video recording (Phase 5)

    func startRecording() {
        guard !isRecording else { return }
        do {
            try cameraService.startRecording()
            isRecording = true
            recordingStartDate = Date()
            recordingDuration = 0
            recordingFileSizeBytes = 0
            startRecordingTimer()
        } catch {
            errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recordingTimerTask?.cancel()
        recordingTimerTask = nil

        cameraService.stopRecording { [weak self] result in
            guard let self else { return }
            self.isRecording = false
            switch result {
            case .success(let recorded):
                Task { @MainActor in
                    await self.saveRecordedVideo(recorded)
                }
            case .failure(let error):
                self.errorMessage = error.errorDescription
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let start = recordingStartDate else { break }
                recordingDuration = Date().timeIntervalSince(start)
                recordingFileSizeBytes = cameraService.currentRecordingFileSizeBytes

                if availableStorageIsCritical() {
                    errorMessage = "Storage is critically low — stopping recording."
                    stopRecording()
                    break
                }
                if ProcessInfo.processInfo.thermalState == .critical {
                    errorMessage = "Device is too hot — stopping recording."
                    stopRecording()
                    break
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func availableStorageIsCritical() -> Bool {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return false
        }
        return capacity < 100 * 1024 * 1024
    }

    private func saveRecordedVideo(_ recorded: RecordedVideo) async {
        let info = RecordedVideoInfo(from: recorded)
        lastRecordedVideo = info
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            return
        }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, CameraError>, Never>) in
            mediaStorage.saveVideo(at: recorded.url) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success:
            let dimensions = recorded.resolution.pixelDimensions
            libraryStore.addVideo(
                fileURL: recorded.url,
                width: dimensions.width,
                height: dimensions.height,
                durationSeconds: recorded.duration,
                formatLabel: recorded.usedProRes ? "Apple ProRes" : "Video"
            )
            try? FileManager.default.removeItem(at: recorded.url)
        case .failure(let error):
            // Leave the temp file in place on failure rather than discarding
            // the only copy of a recording the user just made.
            errorMessage = error.errorDescription
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        if lastRecordedVideo == info {
            lastRecordedVideo = nil
        }
    }

    // MARK: - Computational photography (Phase 6)

    func startHDRCapture(frameCount: Int = 3, stepEV: Float = 2.0) {
        guard hdrTask == nil, focusStackTask == nil else { return }
        let settings = BracketSettings(frameCount: frameCount, exposureStepEV: stepEV)
        computationalProgress = (0, frameCount + 1)

        hdrTask = Task { @MainActor in
            do {
                let frames = try await cameraService.captureExposureBracket(settings: settings) { current, total in
                    Task { @MainActor in
                        self.computationalProgress = (current, total + 1)
                    }
                }
                try Task.checkCancellation()
                let fused = await Task.detached(priority: .userInitiated) {
                    HDRFusionProcessor.fuse(frames: frames)
                }.value
                guard let fused else {
                    errorMessage = "HDR fusion failed."
                    computationalProgress = nil
                    hdrTask = nil
                    return
                }
                computationalProgress = (frameCount + 1, frameCount + 1)
                await saveComputationalResult(fused, originals: frames, kind: .hdrResult)
            } catch is CancellationError {
                // User-cancelled; nothing to report.
            } catch {
                errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
            }
            computationalProgress = nil
            hdrTask = nil
        }
    }

    func cancelHDRCapture() {
        hdrTask?.cancel()
    }

    func startFocusStack(frameCount: Int = 5) {
        guard hdrTask == nil, focusStackTask == nil else { return }
        let settings = FocusStackSettings(frameCount: frameCount)
        computationalProgress = (0, frameCount + 1)

        focusStackTask = Task { @MainActor in
            do {
                let frames = try await cameraService.captureFocusStack(settings: settings) { current, total in
                    Task { @MainActor in
                        self.computationalProgress = (current, total + 1)
                    }
                }
                try Task.checkCancellation()
                let stacked = await Task.detached(priority: .userInitiated) {
                    FocusStackProcessor.stack(frames: frames)
                }.value
                guard let stacked else {
                    errorMessage = "Focus stacking failed."
                    computationalProgress = nil
                    focusStackTask = nil
                    return
                }
                computationalProgress = (frameCount + 1, frameCount + 1)
                await saveComputationalResult(stacked, originals: frames, kind: .focusStackResult)
            } catch is CancellationError {
                // User-cancelled; nothing to report.
            } catch {
                errorMessage = (error as? CameraError)?.errorDescription ?? error.localizedDescription
            }
            computationalProgress = nil
            focusStackTask = nil
        }
    }

    func cancelFocusStack() {
        focusStackTask?.cancel()
    }

    private func saveComputationalResult(_ result: CapturedPhoto, originals: [CapturedPhoto], kind: LibraryItemKind) async {
        let info = CapturedPhotoInfo(from: result)
        lastComputationalResult = info
        guard await mediaStorage.requestAddOnlyAuthorization() else {
            errorMessage = CameraError.permissionDenied.errorDescription
            return
        }
        if case .failure(let error) = await saveAsync(result.data) {
            errorMessage = error.errorDescription
        } else {
            addToLibrary(result, originals: originals, kindOverride: kind)
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        if lastComputationalResult == info {
            lastComputationalResult = nil
        }
    }
}
