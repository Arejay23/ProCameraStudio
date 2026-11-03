import Foundation

/// `url` points at a temporary file; CameraViewModel removes it once it's
/// been saved to Photos (or leaves it in place if the save fails, so the
/// recording isn't silently lost).
struct RecordedVideo {
    let url: URL
    let duration: TimeInterval
    let fileSizeBytes: Int
    let resolution: VideoResolution
    let usedProRes: Bool
}
