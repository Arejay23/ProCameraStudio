import AVFoundation
import SwiftUI

struct ManualControlsView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 14) {
            lensPicker
            isoRow
            shutterRow
            exposureBiasRow
            focusRow
            whiteBalanceRow
            lockAndResetRow
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var lensPicker: some View {
        if viewModel.capabilities.availableLenses.count > 1 {
            Picker("Lens", selection: Binding(
                get: { viewModel.configuration.lensType },
                set: { viewModel.selectLens($0) }
            )) {
                ForEach(viewModel.capabilities.availableLenses, id: \.self) { lens in
                    Text(lens.displayName).tag(lens)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var isoRow: some View {
        let caps = viewModel.capabilities
        let manual = viewModel.configuration.manualISO
        let lower = Double(caps.minISO)
        let upper = Double(max(caps.maxISO, caps.minISO + 1))
        return ManualSliderRow(
            title: "ISO",
            valueText: manual.map { String(format: "%.0f", $0) } ?? "AUTO",
            isManual: manual != nil,
            range: lower...upper,
            value: Binding(
                get: { Double(manual ?? caps.minISO) },
                set: { viewModel.setManualISO(Float($0)) }
            ),
            onReset: { viewModel.setManualISO(nil) }
        )
    }

    private var shutterRow: some View {
        let caps = viewModel.capabilities
        let manual = viewModel.configuration.manualExposureDuration
        let lower = max(caps.minExposureDurationSeconds, 0.0001)
        let upper = max(caps.maxExposureDurationSeconds, lower + 0.0001)
        let manualSeconds = manual.map { CMTimeGetSeconds($0) }
        return ManualSliderRow(
            title: "Shutter",
            valueText: manualSeconds.map(Self.shutterText) ?? "AUTO",
            isManual: manual != nil,
            range: lower...upper,
            value: Binding(
                get: { manualSeconds ?? lower },
                set: { viewModel.setManualExposureDuration(CMTimeMakeWithSeconds($0, preferredTimescale: 1_000_000)) }
            ),
            onReset: { viewModel.setManualExposureDuration(nil) }
        )
    }

    private static func shutterText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private var exposureBiasRow: some View {
        let caps = viewModel.capabilities
        let bias = viewModel.configuration.exposureBias
        let lower = Double(caps.minExposureTargetBias)
        let upper = Double(max(caps.maxExposureTargetBias, caps.minExposureTargetBias + 0.1))
        return ManualSliderRow(
            title: "EV",
            valueText: String(format: "%+.1f", bias ?? 0),
            isManual: bias != nil,
            range: lower...upper,
            value: Binding(
                get: { Double(bias ?? 0) },
                set: { viewModel.setExposureBias(Float($0)) }
            ),
            onReset: { viewModel.setExposureBias(nil) }
        )
    }

    @ViewBuilder
    private var focusRow: some View {
        if viewModel.capabilities.supportsManualFocus {
            let manual = viewModel.configuration.manualFocusLensPosition
            ManualSliderRow(
                title: "Focus",
                valueText: manual.map { String(format: "%.2f", $0) } ?? "AUTO",
                isManual: manual != nil,
                range: 0...1,
                value: Binding(
                    get: { Double(manual ?? 0.5) },
                    set: { viewModel.setManualFocus(Float($0)) }
                ),
                onReset: { viewModel.setManualFocus(nil) }
            )
        }
    }

    private var whiteBalanceRow: some View {
        let caps = viewModel.capabilities
        let manual = viewModel.configuration.manualWhiteBalanceKelvin
        return ManualSliderRow(
            title: "White Balance",
            valueText: manual.map { String(format: "%.0fK", $0) } ?? "AUTO",
            isManual: manual != nil,
            range: Double(caps.minWhiteBalanceKelvin)...Double(caps.maxWhiteBalanceKelvin),
            value: Binding(
                get: { Double(manual ?? 5000) },
                set: { viewModel.setManualWhiteBalance(Float($0)) }
            ),
            onReset: { viewModel.setManualWhiteBalance(nil) }
        )
    }

    private var lockAndResetRow: some View {
        HStack {
            lockToggle("Exposure", isLocked: viewModel.configuration.isExposureLocked, action: viewModel.toggleExposureLock)
            lockToggle("Focus", isLocked: viewModel.configuration.isFocusLocked, action: viewModel.toggleFocusLock)
            Spacer()
            Button("Reset All", action: viewModel.resetToAuto)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func lockToggle(_ title: String, isLocked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isLocked ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(isLocked ? Color.orange : .white.opacity(0.8))
        }
    }
}

/// Shared row shape for every manual control: title, live readout, an "Auto"
/// reset button when a manual value is active, and a slider tinted orange
/// while manual so it's visually distinct from automatic settings.
struct ManualSliderRow: View {
    let title: String
    let valueText: String
    let isManual: Bool
    let range: ClosedRange<Double>
    @Binding var value: Double
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isManual ? Color.orange : .white.opacity(0.7))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                if isManual {
                    Button("Auto", action: onReset)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Slider(value: $value, in: range)
                .tint(isManual ? .orange : .white)
        }
    }
}
