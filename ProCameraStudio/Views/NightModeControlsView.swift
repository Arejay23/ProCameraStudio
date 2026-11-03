import SwiftUI

struct NightModeControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @State private var selectedMode: NightCaptureMode = .noiseReduction
    @State private var saveOriginals = false
    @State private var intervalSeconds: Double = 3

    var body: some View {
        VStack(spacing: 14) {
            stackingSection
            Divider().background(.white.opacity(0.2))
            bracketSection
            Divider().background(.white.opacity(0.2))
            timerAndIntervalSection
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Multi-frame stacking (noise reduction / long exposure / star trails)

    private var stackingSection: some View {
        VStack(spacing: 10) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(NightCaptureMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedMode.explanation)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if !viewModel.isDeviceStable, viewModel.multiFrameProgress != nil {
                Label("Hold steady for best results", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Toggle("Save original frames", isOn: $saveOriginals)
                .font(.caption)
                .toggleStyle(SwitchToggleStyle(tint: .orange))

            if let progress = viewModel.multiFrameProgress {
                progressRow(current: progress.current, total: progress.total) {
                    viewModel.cancelMultiFrameCapture()
                }
            } else {
                Button {
                    viewModel.startMultiFrameCapture(mode: selectedMode, saveOriginalFrames: saveOriginals)
                } label: {
                    Text("Start \(selectedMode.displayName)")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    // MARK: - Exposure bracketing

    private var bracketSection: some View {
        VStack(spacing: 8) {
            Text("Exposure Bracket · 3 frames, ±1 EV")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            if let progress = viewModel.bracketProgress {
                progressRow(current: progress.current, total: progress.total) {
                    viewModel.cancelExposureBracket()
                }
            } else {
                Button("Capture Bracket") {
                    viewModel.startExposureBracket()
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    // MARK: - Timer / interval capture

    private var timerAndIntervalSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Timer")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Picker("Timer", selection: $viewModel.countdownDuration) {
                    Text("Off").tag(0)
                    Text("3s").tag(3)
                    Text("10s").tag(10)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            if viewModel.isIntervalCaptureRunning {
                Button("Stop Interval Capture", role: .destructive) {
                    viewModel.stopIntervalCapture()
                }
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interval capture: every \(Int(intervalSeconds))s")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    HStack {
                        Slider(value: $intervalSeconds, in: 2...30, step: 1)
                            .tint(.white)
                        Button("Start") {
                            viewModel.startIntervalCapture(every: intervalSeconds)
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }

    private func progressRow(current: Int, total: Int, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(current), total: Double(max(total, 1)))
                .tint(.orange)
            HStack {
                Text("Frame \(current) of \(total)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button("Cancel", role: .destructive, action: onCancel)
                    .font(.caption2)
            }
        }
    }
}
