import SwiftUI

enum ActivePanel: Equatable {
    case none
    case manual
    case night
    case video
    case computational
}

struct CameraView: View {
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var libraryStore: LibraryStore
    @State private var activePanel: ActivePanel = .none
    @State private var isGalleryPresented = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: viewModel.session) { devicePoint in
                viewModel.focusAndMeter(at: devicePoint)
            }
            .ignoresSafeArea()

            if viewModel.isGridVisible {
                GridOverlayView()
                    .ignoresSafeArea()
            }

            CameraControlsView(
                viewModel: viewModel,
                activePanel: $activePanel,
                libraryStore: libraryStore,
                onOpenGallery: { isGalleryPresented = true }
            )

            if let countdown = viewModel.countdownSeconds {
                countdownOverlay(countdown)
            }
        }
        .statusBarHidden(true)
        .alert("Camera Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isGalleryPresented) {
            GalleryView(libraryStore: libraryStore)
        }
        .onDisappear {
            viewModel.cancelAllSequenceCapture()
            viewModel.stop()
        }
    }

    private func countdownOverlay(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(radius: 8)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }
}
