import AVFoundation
import ImageIO

/// One instance per in-flight capture; AVCapturePhotoOutput only holds a weak
/// reference to its delegate, so CameraService must keep this object alive
/// until didFinishProcessingPhoto fires.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let requestedFormat: PhotoFormat
    private let completion: (Result<CapturedPhoto, CameraError>) -> Void
    private var didComplete = false

    init(requestedFormat: PhotoFormat, completion: @escaping (Result<CapturedPhoto, CameraError>) -> Void) {
        self.requestedFormat = requestedFormat
        self.completion = completion
    }

    private func finish(_ result: Result<CapturedPhoto, CameraError>) {
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
        // Requested RAW/ProRAW but the device silently handed back a processed
        // image: report that honestly instead of claiming RAW capture succeeded.
        if requestedFormat != .processed, !photo.isRawPhoto {
            finish(.failure(.captureFailed("RAW capture is not available right now; the device returned a processed image instead.")))
            return
        }

        let dimensions = photo.resolvedSettings.photoDimensions
        let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        let exposureTime = (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let fNumber = (exif?[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue

        let captured = CapturedPhoto(
            data: data,
            isRaw: photo.isRawPhoto,
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            fileSizeBytes: data.count,
            requestedFormat: requestedFormat,
            iso: iso,
            exposureTimeSeconds: exposureTime,
            fNumber: fNumber
        )
        finish(.success(captured))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            finish(.failure(.captureFailed(error.localizedDescription)))
        }
    }
}
