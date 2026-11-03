/// `originalFrames` is empty unless MultiFrameCaptureSettings.saveOriginalFrames
/// was true — keeping every frame's Data around is a deliberate, opt-in memory
/// and storage tradeoff, not the default.
struct MultiFrameCaptureResult {
    let stacked: CapturedPhoto
    let originalFrames: [CapturedPhoto]
}
