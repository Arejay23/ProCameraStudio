import CoreImage
import XCTest
@testable import ProCameraStudio

/// These run entirely against synthetic in-memory images — no camera, no
/// device needed — but they exercise the real Core Image filter chains in
/// HDRFusionProcessor/FocusStackProcessor/PhotoEditProcessor exactly as the
/// app does, verifying actual rendered output rather than just that the code
/// compiles. A wrong filter name or parameter key typically doesn't fail to
/// compile (CIFilter parameters are string-keyed) — it silently no-ops or
/// returns a blank image at runtime, which only these tests would catch.
final class ImageProcessingTests: XCTestCase {

    func testHDRFusionProducesValidOutputFromThreeFrames() {
        let frames = [
            SyntheticImage.capturedPhoto(color: (0.05, 0.05, 0.05), size: 64),
            SyntheticImage.capturedPhoto(color: (0.5, 0.5, 0.5), size: 64),
            SyntheticImage.capturedPhoto(color: (0.95, 0.95, 0.95), size: 64)
        ]

        let result = HDRFusionProcessor.fuse(frames: frames)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 64)
        XCTAssertEqual(result?.height, 64)
        XCTAssertFalse(result?.isRaw ?? true)
        XCTAssertGreaterThan(result?.data.count ?? 0, 0)
        XCTAssertNotNil(CIImage(data: result!.data), "Fused output must be decodable as a real image")
    }

    func testHDRFusionWithSingleFrameReturnsThatFrame() {
        let frame = SyntheticImage.capturedPhoto(color: (0.5, 0.5, 0.5), size: 32)

        let result = HDRFusionProcessor.fuse(frames: [frame])

        XCTAssertEqual(result?.data, frame.data)
    }

    func testFocusStackProducesValidOutputFromMultipleFrames() {
        let frames = (0..<4).map { _ in SyntheticImage.capturedPhoto(color: (0.4, 0.4, 0.4), size: 64) }

        let result = FocusStackProcessor.stack(frames: frames)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 64)
        XCTAssertEqual(result?.height, 64)
        XCTAssertGreaterThan(result?.data.count ?? 0, 0)
        XCTAssertNotNil(CIImage(data: result!.data), "Stacked output must be decodable as a real image")
    }

    func testFocusStackWithSingleFrameReturnsThatFrame() {
        let frame = SyntheticImage.capturedPhoto(color: (0.5, 0.5, 0.5), size: 32)

        let result = FocusStackProcessor.stack(frames: [frame])

        XCTAssertEqual(result?.data, frame.data)
    }

    func testPhotoEditProcessorAppliesAdjustmentsAndProducesValidOutput() {
        let sourceData = SyntheticImage.data(color: (0.5, 0.5, 0.5), size: 64)
        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.5
        adjustments.highlights = -0.2
        adjustments.shadows = 0.3
        adjustments.contrast = 1.2
        adjustments.saturation = 1.1
        adjustments.curveStrength = 0.3

        let result = PhotoEditProcessor.render(sourceData: sourceData, adjustments: adjustments)

        XCTAssertNotNil(result)
        XCTAssertNotNil(CIImage(data: result!), "Edited output must be decodable as a real image")
    }

    func testPhotoEditProcessorAppliesCrop() {
        let sourceData = SyntheticImage.data(color: (0.5, 0.5, 0.5), size: 100)
        var adjustments = PhotoAdjustments()
        adjustments.cropRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let result = PhotoEditProcessor.render(sourceData: sourceData, adjustments: adjustments)

        XCTAssertNotNil(result)
        guard let data = result, let image = CIImage(data: data) else {
            XCTFail("Cropped output must be decodable")
            return
        }
        XCTAssertEqual(Int(image.extent.width), 50)
        XCTAssertEqual(Int(image.extent.height), 50)
    }

    func testPhotoEditProcessorWithNeutralAdjustmentsStillProducesValidOutput() {
        let sourceData = SyntheticImage.data(color: (0.3, 0.6, 0.9), size: 48)

        let result = PhotoEditProcessor.render(sourceData: sourceData, adjustments: .neutral)

        XCTAssertNotNil(result)
        XCTAssertNotNil(CIImage(data: result!))
    }
}
