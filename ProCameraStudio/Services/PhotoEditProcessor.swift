import CoreGraphics
import CoreImage

/// Renders PhotoAdjustments onto source image Data via standard Core Image
/// adjustment filters. Never touches the original — always produces new Data
/// for LibraryStore to save as the item's separate edit file. Pure Core
/// Image, no AVFoundation dependency.
///
/// "Curves" here is a single S-curve strength value through CIToneCurve's
/// five fixed control points, not a freeform interactive curve editor —
/// scoped down deliberately rather than left half-built.
enum PhotoEditProcessor {
    static func render(sourceData: Data, adjustments: PhotoAdjustments) -> Data? {
        guard let source = CIImage(data: sourceData) else { return nil }
        var image = source

        if let cropRect = adjustments.cropRect {
            let extent = image.extent
            let pixelRect = CGRect(
                x: extent.origin.x + cropRect.origin.x * extent.width,
                y: extent.origin.y + cropRect.origin.y * extent.height,
                width: cropRect.width * extent.width,
                height: cropRect.height * extent.height
            ).intersection(extent)
            if !pixelRect.isEmpty {
                image = image.cropped(to: pixelRect)
            }
        }

        if adjustments.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": adjustments.exposure])
        }

        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 + adjustments.highlights,
                "inputShadowAmount": adjustments.shadows
            ])
        }

        if adjustments.whiteBalanceShift != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: CGFloat(6500 + adjustments.whiteBalanceShift), y: 0)
            ])
        }

        if adjustments.contrast != 1 || adjustments.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                "inputContrast": adjustments.contrast,
                "inputSaturation": adjustments.saturation
            ])
        }

        if adjustments.curveStrength != 0 {
            image = image.applyingFilter("CIToneCurve", parameters: toneCurvePoints(strength: adjustments.curveStrength))
        }

        let context = CIContext()
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        if let heif = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) {
            return heif
        }
        return context.jpegRepresentation(of: image, colorSpace: colorSpace)
    }

    /// Five fixed points lifted/pulled by `strength` to form a simple S-curve:
    /// positive strength deepens shadows and brightens highlights (more
    /// contrast), negative flattens both toward midtones (less contrast).
    private static func toneCurvePoints(strength: Float) -> [String: Any] {
        let s = CGFloat(strength) * 0.25
        return [
            "inputPoint0": CIVector(x: 0, y: max(0, 0 - s)),
            "inputPoint1": CIVector(x: 0.25, y: max(0, 0.25 - s * 0.5)),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: min(1, 0.75 + s * 0.5)),
            "inputPoint4": CIVector(x: 1, y: min(1, 1 + s))
        ]
    }
}
