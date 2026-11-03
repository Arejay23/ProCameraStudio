/// Parameters for a multi-frame burst (noise reduction, long exposure, or star
/// trails). Transient, request-scoped state — unlike CaptureConfiguration this
/// isn't continuous device state, so it isn't routed through updateConfiguration.
struct MultiFrameCaptureSettings: Equatable {
    var frameCount: Int
    var intervalSeconds: Double
    var algorithm: StackingAlgorithm
    var saveOriginalFrames: Bool
}
