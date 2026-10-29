import SwiftUI

struct CameraControlsView: View {
    let deviceName: String
    let isCapturing: Bool
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void

    var body: some View {
        VStack {
            HStack {
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
                Spacer()
            }
            .padding([.top, .horizontal])

            Spacer()

            HStack {
                Spacer()
                captureButton
                Spacer()
                switchButton
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(.white)
                    .frame(width: 66, height: 66)
                    .opacity(isCapturing ? 0.4 : 1.0)
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel("Capture photo")
    }

    private var switchButton: some View {
        Button(action: onSwitchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Switch camera")
    }
}
