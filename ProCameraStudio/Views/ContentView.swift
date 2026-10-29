import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

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
                CameraView(viewModel: viewModel)
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
