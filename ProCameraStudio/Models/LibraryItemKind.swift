enum LibraryItemKind: String, Codable, CaseIterable {
    case photo
    case rawPhoto
    case video
    case hdrResult
    case focusStackResult
    case nightStackResult

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .rawPhoto: return "RAW"
        case .video: return "Video"
        case .hdrResult: return "HDR"
        case .focusStackResult: return "Focus Stack"
        case .nightStackResult: return "Night Stack"
        }
    }

    var isVideo: Bool { self == .video }
}
