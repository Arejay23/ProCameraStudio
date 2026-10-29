import Photos

/// Owns all Photos-library interaction so later phases (RAW/DNG export, video,
/// gallery) reuse one storage boundary instead of each reimplementing PHPhotoLibrary calls.
protocol MediaStoring: AnyObject {
    func requestAddOnlyAuthorization() async -> Bool
    func savePhotoData(_ data: Data, completion: @escaping (Result<Void, CameraError>) -> Void)
}

final class MediaStorageService: MediaStoring {

    func requestAddOnlyAuthorization() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }

    func savePhotoData(_ data: Data, completion: @escaping (Result<Void, CameraError>) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(.saveFailed(error?.localizedDescription ?? "Unknown error")))
                }
            }
        })
    }
}
