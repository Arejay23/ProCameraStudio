import SwiftUI

struct CameraControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var isManualPanelVisible: Bool

    var body: some View {
        VStack(spacing: 12) {
            topRow
            formatPicker
            Spacer()
            captureInfoBanner
            if isManualPanelVisible {
                ManualControlsView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            bottomRow
        }
    }

    private var topRow: some View {
        HStack {
            Text(viewModel.activeDeviceName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.4), in: Capsule())
            Spacer()
            manualToggleButton
        }
        .padding([.top, .horizontal])
    }

    @ViewBuilder
    private var formatPicker: some View {
        let caps = viewModel.capabilities
        let formats: [PhotoFormat] = [.processed] + (caps.supportsRAW ? [.raw] : []) + (caps.supportsAppleProRAW ? [.appleProRAW] : [])
        if formats.count > 1 {
            Picker("Format", selection: Binding(
                get: { viewModel.configuration.photoFormat },
                set: { viewModel.selectPhotoFormat($0) }
            )) {
                ForEach(formats, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
    }

    @ViewBuilder
    private var captureInfoBanner: some View {
        if let info = viewModel.lastCapture {
            VStack(spacing: 2) {
                Text(info.formatLabel)
                    .font(.caption.bold())
                Text("\(info.width)×\(info.height) · \(String(format: "%.1f", info.fileSizeMB)) MB")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule())
            .transition(.opacity)
        }
    }

    private var manualToggleButton: some View {
        Button(action: { withAnimation { isManualPanelVisible.toggle() } }) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isManualPanelVisible ? .orange : .white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Manual controls")
    }

    private var bottomRow: some View {
        HStack {
            Spacer()
            captureButton
            Spacer()
            switchButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 36)
    }

    private var captureButton: some View {
        Button(action: viewModel.capturePhoto) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(.white)
                    .frame(width: 66, height: 66)
                    .opacity(viewModel.isCapturing ? 0.4 : 1.0)
            }
        }
        .disabled(viewModel.isCapturing)
        .accessibilityLabel("Capture photo")
    }

    private var switchButton: some View {
        Button(action: viewModel.switchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Switch camera")
    }
}
