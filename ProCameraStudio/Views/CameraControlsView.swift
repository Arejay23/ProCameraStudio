import SwiftUI

private enum ModeSelection: Hashable {
    case photo
    case night
    case video
}

struct CameraControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var activePanel: ActivePanel
    @ObservedObject var libraryStore: LibraryStore
    let onOpenGallery: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            topRow
            modePicker
            if viewModel.configuration.captureMode == .photo, !viewModel.isNightModeActive {
                formatPicker
            }
            if viewModel.isNightModeActive {
                nightInlineControls
            }
            recordingHUD
            if viewModel.isHistogramVisible, let data = viewModel.histogramData {
                HistogramView(data: data)
            }
            Spacer()
            captureInfoBanner
            recordingInfoBanner
            computationalInfoBanner
            nightResultBanner
            switch activePanel {
            case .manual:
                ManualControlsView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .night, .video:
                if activePanel == .video {
                    VideoControlsView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    TimingControlsView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            case .computational:
                ComputationalControlsView(viewModel: viewModel)
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
            LevelIndicatorView(rollDegrees: viewModel.levelRollDegrees)
            Spacer()
            trailingToolbarButtons
        }
        .padding([.top, .horizontal])
        .disabled(viewModel.isRecording)
    }

    @ViewBuilder
    private var trailingToolbarButtons: some View {
        if viewModel.configuration.captureMode == .video {
            panelToggleButton(icon: "gearshape", panel: .video, label: "Video settings")
        } else {
            if !viewModel.isNightModeActive {
                panelToggleButton(icon: "wand.and.stars", panel: .computational, label: "HDR and focus stack")
                panelToggleButton(icon: "timer", panel: .night, label: "Bracket, timer, interval")
            }
            directToggleButton(icon: "grid", isOn: viewModel.isGridVisible, label: "Grid") {
                viewModel.isGridVisible.toggle()
            }
            directToggleButton(icon: "waveform", isOn: viewModel.isHistogramVisible, label: "Histogram") {
                viewModel.toggleHistogram()
            }
        }
        panelToggleButton(icon: "slider.horizontal.3", panel: .manual, label: "Manual controls")
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { currentModeSelection },
            set: { setMode($0) }
        )) {
            Text("Photo").tag(ModeSelection.photo)
            Text("Night").tag(ModeSelection.night)
            Text("Video").tag(ModeSelection.video)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .disabled(viewModel.isRecording || viewModel.multiFrameProgress != nil)
    }

    private var currentModeSelection: ModeSelection {
        if viewModel.configuration.captureMode == .video { return .video }
        return viewModel.isNightModeActive ? .night : .photo
    }

    private func setMode(_ mode: ModeSelection) {
        activePanel = .none
        switch mode {
        case .photo:
            viewModel.isNightModeActive = false
            viewModel.switchToPhotoMode()
        case .night:
            viewModel.switchToPhotoMode()
            viewModel.isNightModeActive = true
        case .video:
            viewModel.isNightModeActive = false
            Task { await viewModel.switchToVideoMode() }
        }
    }

    /// Night's stacking-type picker and live explanation/progress, shown
    /// directly in the main control flow rather than behind a toggle button —
    /// this replaces the old floating panel that was reported hard to use.
    private var nightInlineControls: some View {
        VStack(spacing: 6) {
            Picker("Night Mode", selection: $viewModel.selectedNightMode) {
                ForEach(NightCaptureMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .disabled(viewModel.multiFrameProgress != nil)

            if viewModel.multiFrameProgress == nil {
                Text(viewModel.selectedNightMode.explanation)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !viewModel.isDeviceStable, viewModel.multiFrameProgress != nil {
                Label("Hold steady for best results", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
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
        } else if let progress = viewModel.multiFrameProgress, viewModel.isNightModeActive {
            HStack(spacing: 6) {
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("Frame \(progress.current) of \(progress.total)")
                    .font(.caption.monospacedDigit().bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
        } else if viewModel.isBurstCapturing {
            HStack(spacing: 6) {
                Circle().fill(.yellow).frame(width: 8, height: 8)
                Text("\(viewModel.burstCount) shots")
                    .font(.caption.monospacedDigit().bold())
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
            infoBanner(title: info.formatLabel, detail: "\(info.width)×\(info.height) · \(String(format: "%.1f", info.fileSizeMB)) MB")
        }
    }

    @ViewBuilder
    private var recordingInfoBanner: some View {
        if let info = viewModel.lastRecordedVideo {
            infoBanner(
                title: info.usedProRes ? "ProRes Video" : "Video",
                detail: "\(info.resolutionLabel) · \(Self.formattedDuration(info.durationSeconds)) · \(String(format: "%.1f", info.fileSizeMB)) MB"
            )
        }
    }

    @ViewBuilder
    private var computationalInfoBanner: some View {
        if let info = viewModel.lastComputationalResult {
            infoBanner(title: info.formatLabel, detail: "\(info.width)×\(info.height) · \(String(format: "%.1f", info.fileSizeMB)) MB")
        }
    }

    @ViewBuilder
    private var nightResultBanner: some View {
        if let info = viewModel.lastMultiFrameCapture {
            infoBanner(title: info.formatLabel, detail: "\(info.width)×\(info.height) · \(String(format: "%.1f", info.fileSizeMB)) MB")
        }
    }

    private func infoBanner(title: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption.bold())
            Text(detail).font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65), in: Capsule())
        .transition(.opacity)
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

    private func directToggleButton(icon: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? .orange : .white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var bottomRow: some View {
        HStack {
            galleryButton
            Spacer()
            captureOrRecordButton
            Spacer()
            trailingBottomButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 36)
    }

    @ViewBuilder
    private var trailingBottomButton: some View {
        if viewModel.configuration.captureMode == .photo, !viewModel.isNightModeActive {
            burstButton
        } else {
            switchButton
        }
    }

    @ViewBuilder
    private var galleryButton: some View {
        Button(action: onOpenGallery) {
            Group {
                if let latest = libraryStore.items.first,
                   let image = UIImage(contentsOfFile: libraryStore.thumbnailURL(for: latest).path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.4)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.6), lineWidth: 1.5))
        }
        .accessibilityLabel("Open library")
    }

    @ViewBuilder
    private var captureOrRecordButton: some View {
        if viewModel.configuration.captureMode == .video {
            recordButton
        } else if viewModel.isNightModeActive {
            nightStartStopButton
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

    private var nightStartStopButton: some View {
        let isRunning = viewModel.multiFrameProgress != nil
        return Button(action: viewModel.nightCaptureButtonTapped) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRunning ? 8 : 33)
                    .fill(.orange)
                    .frame(width: isRunning ? 32 : 66, height: isRunning ? 32 : 66)
                    .animation(.easeInOut(duration: 0.2), value: isRunning)
            }
        }
        .accessibilityLabel(isRunning ? "Stop night capture" : "Start night capture")
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

    private var burstButton: some View {
        Button(action: {
            if viewModel.isBurstCapturing {
                viewModel.stopBurstCapture()
            } else {
                viewModel.startBurstCapture()
            }
        }) {
            Image(systemName: viewModel.isBurstCapturing ? "stop.fill" : "square.stack.3d.up")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(viewModel.isBurstCapturing ? .yellow : .white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(viewModel.isBurstCapturing ? "Stop burst capture" : "Start burst capture")
    }
}
