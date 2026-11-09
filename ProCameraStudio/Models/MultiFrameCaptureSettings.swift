/// Parameters for a multi-frame burst (noise reduction, long exposure, or star
/// trails). Transient, request-scoped state — unlike CaptureConfiguration this
/// isn't continuous device state, so it isn't routed through updateConfiguration.
struct MultiFrameCaptureSettings: Equatable {
    /// For bounded captures, the actual target. For unbounded captures, a
    /// safety ceiling only — the real stop condition is cancellation.
    var frameCount: Int
    var intervalSeconds: Double
    var algorithm: StackingAlgorithm
    var saveOriginalFrames: Bool
    var isUnbounded: Bool = false
}
