/// Normalized (0...1) per-channel bin heights for display — the tallest bin
/// across all three channels is scaled to 1.0, matching how camera-app
/// histograms conventionally display (relative height, not absolute pixel count).
struct HistogramData: Equatable {
    let red: [Float]
    let green: [Float]
    let blue: [Float]
}
