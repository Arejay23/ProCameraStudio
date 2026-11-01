import Foundation

/// What CameraService actually captured. `isRaw` is AVCapturePhoto's own
/// ground-truth flag, not an assumption based on what was requested — the
/// capture pipeline cross-checks this before ever reporting success.
struct CapturedPhoto {
    let data: Data
    let isRaw: Bool
    let width: Int
    let height: Int
    let fileSizeBytes: Int
    let requestedFormat: PhotoFormat
    let iso: Double?
    let exposureTimeSeconds: Double?
    let fNumber: Double?
}
