import SwiftUI

struct VideoControlsView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 14) {
            resolutionRow
            frameRateRow
            if viewModel.videoCapabilities.supportsProRes {
                proResRow
            }
            Text("Manual exposure, ISO, shutter and white balance from the Manual panel apply to video too.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.5 : 1)
    }

    private var resolutionRow: some View {
        HStack {
            Text("Resolution")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Picker("Resolution", selection: Binding(
                get: { viewModel.configuration.videoResolution },
                set: { viewModel.selectVideoResolution($0) }
            )) {
                ForEach(viewModel.videoCapabilities.availableResolutions, id: \.self) { resolution in
                    Text(resolution.displayName).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }

    private var frameRateRow: some View {
        HStack {
            Text("Frame Rate")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Picker("Frame Rate", selection: Binding(
                get: { viewModel.configuration.videoFrameRate },
                set: { viewModel.selectVideoFrameRate($0) }
            )) {
                ForEach(viewModel.videoCapabilities.availableFrameRates, id: \.self) { rate in
                    Text("\(Int(rate))").tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }

    private var proResRow: some View {
        Toggle("Apple ProRes", isOn: Binding(
            get: { viewModel.configuration.useProResVideo },
            set: { viewModel.toggleProResVideo($0) }
        ))
        .font(.caption)
        .toggleStyle(SwitchToggleStyle(tint: .orange))
    }
}
