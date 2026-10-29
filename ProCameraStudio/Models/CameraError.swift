import Foundation

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case deviceUnavailable
    case configurationFailed(String)
    case captureFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera or Photos access is required. Enable it in Settings to use ProCamera Studio."
        case .deviceUnavailable:
            return "No camera is available on this device for the requested position."
        case .configurationFailed(let reason):
            return "Camera could not be configured: \(reason)"
        case .captureFailed(let reason):
            return "Photo capture failed: \(reason)"
        case .saveFailed(let reason):
            return "Could not save photo: \(reason)"
        }
    }
}
