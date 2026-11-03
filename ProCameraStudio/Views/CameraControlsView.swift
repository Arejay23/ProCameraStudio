import SwiftUI

struct CameraControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var activePanel: ActivePanel

    var body: some View {
        VStack(spacing: 12) {
            topRow
            modePicker
            if viewModel.configuration.captureMode == .photo {
                formatPicker
            }
            recordingHUD
            Spacer()
            captureInfoBanner
            recordingInfoBanner
            switch activePanel {
            case .manual:
                ManualControlsView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .night:
                NightModeControlsView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .video:
                VideoControlsView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .none:
                EmptyView()
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
            if viewModel.configuration.captureMode == .video {
                panelToggleButton(icon: "gearshape", panel: .video, label: "Video settings")
            } else {
                panelToggleButton(icon: "moon.stars", panel: .night, label: "Night mode controls")
            }
            panelToggleButton(icon: "slider.horizontal.3", panel: .manual, label: "Manual controls")
        }
        .padding([.top, .horizontal])
        .disabled(viewModel.isRecording)
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.configuration.captureMode },
            set: { newMode in
                if newMode == .video {
                    Task { await viewModel.switchToVideoMode() }
                } else {
                    viewModel.switchToPhotoMode()
                }
            }
        )) {
            Text("Photo").tag(CaptureMode.photo)
            Text("Video").tag(CaptureMode.video)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 160)
        .disabled(viewModel.isRecording)
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
    private var recordingHUD: some View {
        if viewModel.isRecording {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(Self.formattedDuration(viewModel.recordingDuration))
                    .font(.caption.monospacedDigit().bold())
                Text("· \(String(format: "%.0f", Double(viewModel.recordingFileSizeBytes) / 1_000_000)) MB")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
        }
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
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

    @ViewBuilder
    private var recordingInfoBanner: some View {
        if let info = viewModel.lastRecordedVideo {
            VStack(spacing: 2) {
                Text(info.usedProRes ? "ProRes Video" : "Video")
                    .font(.caption.bold())
                Text("\(info.resolutionLabel) · \(Self.formattedDuration(info.durationSeconds)) · \(String(format: "%.1f", info.fileSizeMB)) MB")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule())
            .transition(.opacity)
        }
    }

    private func panelToggleButton(icon: String, panel: ActivePanel, label: String) -> some View {
        Button(action: {
            withAnimation { activePanel = (activePanel == panel) ? .none : panel }
        }) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(activePanel == panel ? .orange : .white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var bottomRow: some View {
        HStack {
            Spacer()
            captureOrRecordButton
            Spacer()
            switchButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 36)
    }

    @ViewBuilder
    private var captureOrRecordButton: some View {
        if viewModel.configuration.captureMode == .video {
            recordButton
        } else {
            captureButton
        }
    }

    private var captureButton: some View {
        Button(action: viewModel.captureButtonTapped) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(viewModel.countdownSeconds != nil ? .orange : .white)
                    .frame(width: 66, height: 66)
                    .opacity(viewModel.isCapturing ? 0.4 : 1.0)
            }
        }
        .disabled(viewModel.isCapturing)
        .accessibilityLabel("Capture photo")
    }

    private var recordButton: some View {
        Button(action: {
            if viewModel.isRecording {
                viewModel.stopRecording()
            } else {
                viewModel.startRecording()
            }
        }) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: viewModel.isRecording ? 8 : 33)
                    .fill(.red)
                    .frame(width: viewModel.isRecording ? 32 : 66, height: viewModel.isRecording ? 32 : 66)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
            }
        }
        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
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
