import SwiftUI

struct ContentView: View {
    @StateObject private var libraryStore: LibraryStore
    @StateObject private var viewModel: CameraViewModel

    init() {
        let store = LibraryStore()
        _libraryStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: CameraViewModel(libraryStore: store))
    }

    var body: some View {
        Group {
            switch viewModel.authorizationState {
            case .unknown:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            case .authorized:
                CameraView(viewModel: viewModel, libraryStore: libraryStore)
            case .denied:
                PermissionDeniedView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.start()
        }
    }
}
