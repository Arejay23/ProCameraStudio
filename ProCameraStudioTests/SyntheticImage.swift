import CoreImage
@testable import ProCameraStudio

/// Generates small solid-color test images so HDRFusionProcessor/
/// FocusStackProcessor/PhotoEditProcessor can be exercised with real Core
/// Image rendering in unit tests — catching wrong filter names/parameters
/// that would otherwise only surface (or silently no-op) at runtime on a
/// physical device, the exact risk class that caused a shipped crash in
/// Phase 3.
enum SyntheticImage {
    static func data(color: (Float, Float, Float), size: Int) -> Data {
        let ciColor = CIColor(red: CGFloat(color.0), green: CGFloat(color.1), blue: CGFloat(color.2))
        let image = CIImage(color: ciColor).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let heif = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) {
            return heif
        }
        return context.jpegRepresentation(of: image, colorSpace: colorSpace) ?? Data()
    }

    static func capturedPhoto(color: (Float, Float, Float), size: Int) -> CapturedPhoto {
        let imageData = data(color: color, size: size)
        return CapturedPhoto(
            data: imageData,
            isRaw: false,
            width: size,
            height: size,
            fileSizeBytes: imageData.count,
            requestedFormat: .processed,
            iso: 100,
            exposureTimeSeconds: 1.0 / 60,
            fNumber: 1.8
        )
    }
}
