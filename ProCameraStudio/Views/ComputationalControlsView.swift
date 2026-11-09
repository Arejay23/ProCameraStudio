import SwiftUI

struct ComputationalControlsView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Computational Photography")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.85))

            if let progress = viewModel.computationalProgress {
                progressRow(current: progress.current, total: progress.total)
            } else {
                hdrSection
                Divider().background(.white.opacity(0.2))
                focusStackSection
            }
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var hdrSection: some View {
        VStack(spacing: 6) {
            Text("HDR merges 3 bracketed exposures (±2 EV) to recover highlight and shadow detail. Computational fusion, not a single sensor capture — see README for how it works.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Button("Capture HDR") {
                viewModel.startHDRCapture()
            }
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var focusStackSection: some View {
        VStack(spacing: 6) {
            Text("Focus Stack captures 5 frames sweeping near-to-far focus and merges the sharpest regions of each. Use a tripod — handheld movement between frames hurts the result.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Button("Capture Focus Stack") {
                viewModel.startFocusStack()
            }
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private func progressRow(current: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(current), total: Double(max(total, 1)))
                .tint(.orange)
            HStack {
                Text(current < total ? "Capturing frame \(current) of \(total - 1)…" : "Processing…")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button("Cancel", role: .destructive) {
                    viewModel.cancelHDRCapture()
                    viewModel.cancelFocusStack()
                }
                .font(.caption2)
            }
        }
    }
}
