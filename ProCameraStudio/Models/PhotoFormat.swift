/// The requested capture format. RAW/ProRAW availability depends on the active
/// device/lens/format, so CameraService validates this against real capabilities
/// and falls back to .processed — reporting that back — rather than silently
/// claiming RAW capture succeeded when it didn't.
enum PhotoFormat: String, CaseIterable, Hashable {
    case processed
    case raw
    case appleProRAW

    var displayName: String {
        switch self {
        case .processed: return "Photo"
        case .raw: return "RAW"
        case .appleProRAW: return "ProRAW"
        }
    }
}
