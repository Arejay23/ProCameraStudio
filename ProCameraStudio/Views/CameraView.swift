import SwiftUI

struct CameraView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            CameraControlsView(
                deviceName: viewModel.activeDeviceName,
                isCapturing: viewModel.isCapturing,
                onCapture: viewModel.capturePhoto,
                onSwitchCamera: viewModel.switchCamera
            )
        }
        .statusBarHidden(true)
        .alert("Camera Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onDisappear {
            viewModel.stop()
        }
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
