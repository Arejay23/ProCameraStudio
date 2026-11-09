import CoreGraphics
import CoreImage

/// Merges exposure-bracketed frames (see BracketSettings/captureExposureBracket)
/// into one image via highlight/shadow recovery blending — a simplified, real
/// exposure-fusion technique, not full Mertens fusion: the darkest frame fills
/// in detail where the base frame is blown out, the brightest frame fills in
/// detail where the base is crushed, each blend weighted down where the frames
/// disagree (a difference mask) to reduce ghosting from scene motion between
/// shots. No frame alignment is performed — same tripod assumption as Phase 4's
/// FrameStacker, stated here rather than silently assumed. Pure Core Image, no
/// AVFoundation dependency, so this never touches the live camera session.
enum HDRFusionProcessor {
    private static let luminanceVector: [String: Any] = [
        "inputRVector": CIVector(x: 0.299, y: 0.299, z: 0.299, w: 0),
        "inputGVector": CIVector(x: 0.587, y: 0.587, z: 0.587, w: 0),
        "inputBVector": CIVector(x: 0.114, y: 0.114, z: 0.114, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
    ]

    /// `frames` must be in bracket capture order (darkest to brightest), which
    /// is what CameraService.captureExposureBracket produces.
    static func fuse(frames: [CapturedPhoto]) -> CapturedPhoto? {
        guard frames.count >= 2 else { return frames.first }
        guard
            let dark = CIImage(data: frames.first!.data),
            let bright = CIImage(data: frames.last!.data)
        else { return nil }
        let baseCaptured = frames[frames.count / 2]
        guard let base = CIImage(data: baseCaptured.data) else { return nil }

        let baseLuminance = base.applyingFilter("CIColorMatrix", parameters: luminanceVector)

        // ~1 where base is near-blown (luminance above ~0.6), ~0 elsewhere.
        let highlightMask = clamped(baseLuminance, scale: 4, bias: -2.4)
        // ~1 where base is near-crushed (luminance below ~0.4), ~0 elsewhere.
        let shadowMask = clamped(baseLuminance, scale: -4, bias: 1.6)

        let safeHighlightMask = highlightMask.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: suppressionMask(base: base, other: dark)
        ])
        let safeShadowMask = shadowMask.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: suppressionMask(base: base, other: bright)
        ])

        let highlightRecovered = dark.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: base,
            kCIInputMaskImageKey: safeHighlightMask
        ])
        let fused = bright.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: highlightRecovered,
            kCIInputMaskImageKey: safeShadowMask
        ])
        let toneMapped = fused.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 0.9,
            "inputShadowAmount": 0.6
        ])

        guard let data = render(toneMapped) else { return nil }
        return CapturedPhoto(
            data: data,
            isRaw: false,
            width: Int(toneMapped.extent.width),
            height: Int(toneMapped.extent.height),
            fileSizeBytes: data.count,
            requestedFormat: .processed,
            iso: baseCaptured.iso,
            exposureTimeSeconds: baseCaptured.exposureTimeSeconds,
            fNumber: baseCaptured.fNumber
        )
    }

    /// ~1 where `other` matches `base` closely (safe to blend), ~0 where they
    /// differ a lot (likely scene motion — don't pull detail from there).
    private static func suppressionMask(base: CIImage, other: CIImage) -> CIImage {
        let difference = base
            .applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: other])
            .applyingFilter("CIColorMatrix", parameters: luminanceVector)
        return clamped(difference, scale: -6, bias: 1)
    }

    private static func clamped(_ image: CIImage, scale: CGFloat, bias: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
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
