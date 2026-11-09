import Foundation

/// A named snapshot of manual settings, saved for quick recall. Stores
/// exposure duration as seconds (Double) rather than CMTime since CMTime
/// isn't Codable.
struct CameraPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var manualISO: Float?
    var manualExposureDurationSeconds: Double?
    var exposureBias: Float?
    var manualFocusLensPosition: Float?
    var manualWhiteBalanceKelvin: Float?
    var lensType: LensType
    var photoFormat: PhotoFormat
}
