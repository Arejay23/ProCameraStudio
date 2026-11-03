/// Each frame is captured at a different exposure-bias offset, centered on
/// whatever bias is currently active, then every frame is saved individually
/// — bracketing gives the user several exposures to choose from; merging them
/// into one HDR result is Phase 6's job, not this one.
struct BracketSettings: Equatable {
    var frameCount: Int
    var exposureStepEV: Float
}
