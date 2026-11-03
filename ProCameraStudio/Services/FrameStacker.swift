import CoreImage
import CoreGraphics

/// Merges a sequence of captured frames into one image using CIImage's lazy
/// filter graph — only the accumulated result and the current frame are ever
/// materialized, not every frame at once, so memory stays roughly bounded to
/// one frame's size regardless of how many frames are stacked.
///
/// `.average` reduces noise / simulates motion blur and light trails.
/// `.maximum` keeps the brightest value at each pixel, for star trails.
/// Neither performs feature-based alignment between frames — this assumes a
/// relatively stable camera (tripod-friendly, not handheld-shake-corrected).
final class FrameStacker {
    private let algorithm: StackingAlgorithm
    private let context = CIContext()
    private var accumulated: CIImage?
    private var frameCount = 0

    init(algorithm: StackingAlgorithm) {
        self.algorithm = algorithm
    }

    func add(_ frame: CapturedPhoto) {
        guard let image = CIImage(data: frame.data) else { return }
        frameCount += 1

        guard let existing = accumulated else {
            accumulated = image
            return
        }

        switch algorithm {
        case .maximum:
            accumulated = existing.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: image])
        case .average:
            // Running average: newAvg = existing * (n-1)/n + frame * 1/n
            let n = CGFloat(frameCount)
            let weightedExisting = existing.applyingFilter("CIColorMatrix", parameters: Self.scaleParameters((n - 1) / n))
            let weightedFrame = image.applyingFilter("CIColorMatrix", parameters: Self.scaleParameters(1 / n))
            accumulated = weightedExisting.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: weightedFrame])
        }
    }

    /// Renders the accumulated result to HEIC (falling back to JPEG). Returns
    /// nil if no frames were ever added.
    func finish() -> CapturedPhoto? {
        guard let accumulated else { return nil }
        let extent = accumulated.extent
        let colorSpace = accumulated.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        let data: Data
        if let heif = context.heifRepresentation(of: accumulated, format: .RGBA8, colorSpace: colorSpace) {
            data = heif
        } else if let jpeg = context.jpegRepresentation(of: accumulated, colorSpace: colorSpace) {
            data = jpeg
        } else {
            return nil
        }

        return CapturedPhoto(
            data: data,
            isRaw: false,
            width: Int(extent.width),
            height: Int(extent.height),
            fileSizeBytes: data.count,
            requestedFormat: .processed,
            iso: nil,
            exposureTimeSeconds: nil,
            fNumber: nil
        )
    }

    private static func scaleParameters(_ scale: CGFloat) -> [String: Any] {
        [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]
    }
}
