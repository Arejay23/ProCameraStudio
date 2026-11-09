import Foundation

/// A captured item in the app's own local library — not a reference into the
/// Photos library. Everything here lives in the app sandbox so the gallery
/// never needs broader Photos read access than the add-only permission
/// granted since Phase 1.
struct LibraryItemRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: LibraryItemKind
    let captureDate: Date
    var mediaFileName: String
    var thumbnailFileName: String
    var width: Int
    var height: Int
    var fileSizeBytes: Int
    var formatLabel: String
    var iso: Double?
    var exposureTimeSeconds: Double?
    var fNumber: Double?
    var durationSeconds: Double?

    /// Source frames preserved for before/after comparison (HDR brackets,
    /// focus-stack frames, night-stack originals when "save originals" was on).
    var originalFileNames: [String] = []

    /// Non-destructive: the original media file is never overwritten. Set once
    /// an edit has been saved; nil means unedited.
    var editFileName: String?

    var hasOriginalsToCompare: Bool { !originalFileNames.isEmpty }
    var hasEdit: Bool { editFileName != nil }
}
