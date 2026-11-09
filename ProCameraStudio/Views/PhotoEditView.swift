import SwiftUI

struct PhotoEditView: View {
    @ObservedObject var libraryStore: LibraryStore
    let item: LibraryItemRecord
    @Environment(\.dismiss) private var dismiss

    @State private var adjustments = PhotoAdjustments()
    @State private var previewImage: UIImage?
    @State private var sourceData: Data?
    @State private var selectedCropPreset: CropPreset = .original
    @State private var isSaving = false

    enum CropPreset: String, CaseIterable {
        case original, square, fourThree, sixteenNine

        var displayName: String {
            switch self {
            case .original: return "Original"
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .sixteenNine: return "16:9"
            }
        }

        var aspectRatio: CGFloat? {
            switch self {
            case .original: return nil
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                ScrollView {
                    controls
                }
                .frame(maxHeight: 280)
                .background(.black.opacity(0.9))
            }
            .background(Color.black)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || adjustments.isNeutral)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            loadSource()
        }
        .onChange(of: adjustments) { _, _ in
            updatePreview()
        }
    }

    private var previewArea: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            cropRow
            editSlider("Exposure", value: $adjustments.exposure, range: -2...2)
            editSlider("Highlights", value: $adjustments.highlights, range: -1...1)
            editSlider("Shadows", value: $adjustments.shadows, range: -1...1)
            editSlider("White Balance", value: $adjustments.whiteBalanceShift, range: -2000...2000)
            editSlider("Contrast", value: $adjustments.contrast, range: 0...2)
            editSlider("Saturation", value: $adjustments.saturation, range: 0...2)
            editSlider("Curve", value: $adjustments.curveStrength, range: -1...1)
            Button("Reset All") {
                adjustments = .neutral
                selectedCropPreset = .original
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
    }

    private var cropRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Crop").font(.caption).foregroundStyle(.white.opacity(0.7))
            Picker("Crop", selection: $selectedCropPreset) {
                ForEach(CropPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
        }
        .onChange(of: selectedCropPreset) { _, newValue in
            adjustments.cropRect = Self.cropRect(for: newValue, sourceSize: CGSize(width: item.width, height: item.height))
        }
    }

    private func editSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
            }
            Slider(value: value, in: range).tint(.orange)
        }
    }

    private func loadSource() {
        let url = libraryStore.mediaURL(for: item)
        sourceData = try? Data(contentsOf: url)
        updatePreview()
    }

    /// Re-renders the full adjustment pipeline at full resolution on every
    /// change rather than a separate downscaled preview path — simpler, and
    /// CIContext is GPU-backed so it's fast enough for most photos, but a
    /// 48MP ProRAW edit can visibly lag while dragging a slider. A dedicated
    /// low-res preview pipeline would fix that; left for later polish.
    private func updatePreview() {
        guard let sourceData else { return }
        let currentAdjustments = adjustments
        Task.detached(priority: .userInitiated) {
            guard let rendered = PhotoEditProcessor.render(sourceData: sourceData, adjustments: currentAdjustments) else { return }
            let image = UIImage(data: rendered)
            await MainActor.run {
                previewImage = image
            }
        }
    }

    private func save() {
        guard let sourceData else { return }
        isSaving = true
        let currentAdjustments = adjustments
        Task.detached(priority: .userInitiated) {
            let rendered = PhotoEditProcessor.render(sourceData: sourceData, adjustments: currentAdjustments)
            await MainActor.run {
                if let rendered {
                    libraryStore.saveEdit(for: item, editedData: rendered)
                }
                isSaving = false
                dismiss()
            }
        }
    }

    private static func cropRect(for preset: CropPreset, sourceSize: CGSize) -> CGRect? {
        guard let aspect = preset.aspectRatio, sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let sourceAspect = sourceSize.width / sourceSize.height
        var width: CGFloat = 1
        var height: CGFloat = 1
        if aspect > sourceAspect {
            height = sourceAspect / aspect
        } else {
            width = aspect / sourceAspect
        }
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}
