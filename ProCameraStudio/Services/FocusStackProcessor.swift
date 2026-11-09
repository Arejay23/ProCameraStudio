import CoreGraphics
import CoreImage

/// Merges frames captured at different focus distances into one image, each
/// pixel pulled from whichever source frame is sharpest there. Sharpness is a
/// Laplacian edge-energy map (squared, so it's non-negative and peaks at
/// high-contrast edges) — a standard, simple sharpness proxy, not a claim that
/// true optical detail absent from every source frame has been recovered.
/// Pure Core Image, no AVFoundation dependency.
enum FocusStackProcessor {
    static func stack(frames: [CapturedPhoto]) -> CapturedPhoto? {
        guard let first = frames.first, let firstImage = CIImage(data: first.data) else { return nil }
        guard frames.count > 1 else { return first }

        var accumulated = firstImage
        var accumulatedSharpness = sharpness(of: firstImage)

        for captured in frames.dropFirst() {
            guard let frame = CIImage(data: captured.data) else { continue }
            let frameSharpness = sharpness(of: frame)

            // ~1 where this frame is sharper than everything accumulated so far.
            let selectMask = frameSharpness
                .applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: accumulatedSharpness])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 8, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 8, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 8, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
                ])
                .applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                ])

            accumulated = frame.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: accumulated,
                kCIInputMaskImageKey: selectMask
            ])
            accumulatedSharpness = accumulatedSharpness.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: frameSharpness
            ])
        }

        guard let data = render(accumulated) else { return nil }
        let reference = frames[frames.count / 2]
        return CapturedPhoto(
            data: data,
            isRaw: false,
            width: Int(accumulated.extent.width),
            height: Int(accumulated.extent.height),
            fileSizeBytes: data.count,
            requestedFormat: .processed,
            iso: reference.iso,
            exposureTimeSeconds: reference.exposureTimeSeconds,
            fNumber: reference.fNumber
        )
    }

    private static func sharpness(of image: CIImage) -> CIImage {
        let laplacian = image.clampedToExtent()
            .applyingFilter("CIConvolution3X3", parameters: [
                "inputWeights": CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9),
                "inputBias": 0
            ])
            .cropped(to: image.extent)
        let squared = laplacian.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: laplacian])
        return squared.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
            "inputGVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
            "inputBVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    private static func render(_ image: CIImage) -> Data? {
        let context = CIContext()
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        if let heif = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) {
            return heif
        }
        return context.jpegRepresentation(of: image, colorSpace: colorSpace)
    }
}
