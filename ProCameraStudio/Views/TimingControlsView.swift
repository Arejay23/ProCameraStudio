import SwiftUI

/// Exposure bracketing, countdown timer, and interval capture — grouped
/// together because none of them are specific to Night mode (bracket and
/// timer are just as useful for a normal photo), unlike the old
/// NightModeControlsView this replaces, which bundled them in with the
/// night-stacking controls for no real reason beyond "it's an extra panel."
struct TimingControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @State private var intervalSeconds: Double = 3

    var body: some View {
        VStack(spacing: 14) {
            bracketSection
            Divider().background(.white.opacity(0.2))
            timerAndIntervalSection
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

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
