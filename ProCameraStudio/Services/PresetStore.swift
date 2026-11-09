import AVFoundation
import Foundation

/// Saved manual-setting snapshots, persisted to UserDefaults — small, simple
/// data that doesn't need LibraryStore's file-based approach. Owned directly
/// by CameraViewModel rather than shared/injected: nothing outside the camera
/// screen needs presets, unlike LibraryStore which the gallery also reads.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [CameraPreset] = []

    private let defaultsKey = "com.procamerastudio.presets"

    init() {
        load()
    }

    func save(name: String, from configuration: CaptureConfiguration) {
        let preset = CameraPreset(
            id: UUID(),
            name: name,
            manualISO: configuration.manualISO,
            manualExposureDurationSeconds: configuration.manualExposureDuration.map { CMTimeGetSeconds($0) },
            exposureBias: configuration.exposureBias,
            manualFocusLensPosition: configuration.manualFocusLensPosition,
            manualWhiteBalanceKelvin: configuration.manualWhiteBalanceKelvin,
            lensType: configuration.lensType,
            photoFormat: configuration.photoFormat
        )
        presets.append(preset)
        persist()
    }

    func delete(_ preset: CameraPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        presets = (try? JSONDecoder().decode([CameraPreset].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
