import AVFoundation

/// One instance per recording. AVCaptureFileOutput only holds a weak reference
/// to its delegate, so CameraService must keep this alive until the delegate
/// callback fires — same reasoning as PhotoCaptureProcessor.
final class VideoRecordingProcessor: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let resolution: VideoResolution
    private let usedProRes: Bool
    var completion: ((Result<RecordedVideo, CameraError>) -> Void)?

    init(resolution: VideoResolution, usedProRes: Bool) {
        self.resolution = resolution
        self.usedProRes = usedProRes
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            // AVFoundation can report a "successful" recording through this
            // error parameter (e.g. stopped due to interruption) with the file
            // still valid — check the flag rather than treating every non-nil
            // error as a real failure.
            let nsError = error as NSError
            let finishedSuccessfully = (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            if !finishedSuccessfully {
                completion?(.failure(.captureFailed(error.localizedDescription)))
                return
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int) ?? 0
        let asset = AVURLAsset(url: outputFileURL)
        let resolution = resolution
        let usedProRes = usedProRes
        let completion = completion

        Task {
            let duration = (try? await asset.load(.duration)) ?? .zero
            let recorded = RecordedVideo(
                url: outputFileURL,
                duration: CMTimeGetSeconds(duration),
                fileSizeBytes: fileSize,
                resolution: resolution,
                usedProRes: usedProRes
            )
            completion?(.success(recorded))
        }
    }
}
