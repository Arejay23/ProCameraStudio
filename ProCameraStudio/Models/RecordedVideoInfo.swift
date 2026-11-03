import Foundation

/// Lightweight, Equatable display model for the post-recording banner —
/// metadata only, mirroring CapturedPhotoInfo's reasoning (the full
/// RecordedVideo carries a file URL, not raw bytes, so size isn't the same
/// concern here, but the display/data-layer split stays consistent).
struct RecordedVideoInfo: Equatable {
    let durationSeconds: TimeInterval
    let fileSizeBytes: Int
    let resolutionLabel: String
    let usedProRes: Bool

    var fileSizeMB: Double { Double(fileSizeBytes) / 1_000_000 }

    init(from recorded: RecordedVideo) {
        durationSeconds = recorded.duration
        fileSizeBytes = recorded.fileSizeBytes
        resolutionLabel = recorded.resolution.displayName
        usedProRes = recorded.usedProRes
    }
}
