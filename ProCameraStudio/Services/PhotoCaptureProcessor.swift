import AVFoundation

/// One instance per in-flight capture; AVCapturePhotoOutput only holds a weak
/// reference to its delegate, so CameraService must keep this object alive
/// until didFinishProcessingPhoto fires.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, CameraError>) -> Void
    private var didComplete = false

    init(completion: @escaping (Result<Data, CameraError>) -> Void) {
        self.completion = completion
    }

    private func finish(_ result: Result<Data, CameraError>) {
        guard !didComplete else { return }
        didComplete = true
        completion(result)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            finish(.failure(.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            finish(.failure(.captureFailed("No image data produced")))
            return
        }
        finish(.success(data))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            finish(.failure(.captureFailed(error.localizedDescription)))
        }
    }
}
