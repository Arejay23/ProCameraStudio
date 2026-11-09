import CoreGraphics

/// Non-destructive adjustment values. Never applied to the original file —
/// PhotoEditProcessor renders a new file from the original + these values,
/// and LibraryStore stores that separately (LibraryItemRecord.editFileName).
struct PhotoAdjustments: Equatable {
    var exposure: Float = 0          // EV, roughly -2...2
    var highlights: Float = 0        // -1...1
    var shadows: Float = 0           // -1...1
    var whiteBalanceShift: Float = 0 // Kelvin delta, roughly -2000...2000
    var contrast: Float = 1          // 0...2, 1 = neutral
    var saturation: Float = 1        // 0...2, 1 = neutral
    var curveStrength: Float = 0     // -1...1, simple S-curve amount (not a full curve editor)
    var cropRect: CGRect?            // normalized 0...1 in the source image; nil = uncropped

    static let neutral = PhotoAdjustments()

    var isNeutral: Bool { self == .neutral }
}
