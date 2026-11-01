import Foundation

/// Lightweight, Equatable display model for the capture-result banner — holds
/// metadata only, not the (potentially 100MB+ for ProRAW) image Data, since
/// this is what sits in @Published state for SwiftUI to diff.
struct CapturedPhotoInfo: Equatable {
    let formatLabel: String
    let width: Int
    let height: Int
    let fileSizeBytes: Int
    let iso: Double?
    let exposureTimeSeconds: Double?
    let fNumber: Double?

    var fileSizeMB: Double { Double(fileSizeBytes) / 1_000_000 }

    init(from captured: CapturedPhoto) {
        if captured.isRaw {
            formatLabel = captured.requestedFormat == .appleProRAW ? "Apple ProRAW" : "RAW (DNG)"
        } else {
            formatLabel = "HEIC"
        }
        width = captured.width
        height = captured.height
        fileSizeBytes = captured.fileSizeBytes
        iso = captured.iso
        exposureTimeSeconds = captured.exposureTimeSeconds
        fNumber = captured.fNumber
    }
}
