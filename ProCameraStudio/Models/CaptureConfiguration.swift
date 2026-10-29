import AVFoundation

/// Minimal capture configuration for Phase 1 (auto exposure/focus/white balance only).
/// Manual controls (Phase 2) and format selection (Phase 3) extend this type rather than
/// replacing CameraServicing's shape.
struct CaptureConfiguration: Equatable {
    var position: AVCaptureDevice.Position = .back
}
