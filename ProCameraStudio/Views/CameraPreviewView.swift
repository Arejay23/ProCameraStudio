import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.previewView = view

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    final class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void
        weak var previewView: PreviewView?

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewView else { return }
            let layerPoint = gesture.location(in: previewView)
            let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            previewView.showFocusReticle(at: layerPoint)
            onTap(devicePoint)
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Brief visual feedback for tap-to-focus/meter, drawn directly in UIKit
    /// rather than coordinated through a separate SwiftUI overlay, since that
    /// would need to replicate this view's exact coordinate mapping.
    func showFocusReticle(at point: CGPoint) {
        let size: CGFloat = 72
        let reticle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        reticle.center = point
        reticle.layer.borderColor = UIColor.systemOrange.cgColor
        reticle.layer.borderWidth = 1.5
        reticle.layer.cornerRadius = 4
        reticle.alpha = 0
        reticle.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        reticle.isUserInteractionEnabled = false
        addSubview(reticle)

        UIView.animate(withDuration: 0.2, animations: {
            reticle.alpha = 1
            reticle.transform = .identity
        }, completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0.6, options: [], animations: {
                reticle.alpha = 0
            }, completion: { _ in
                reticle.removeFromSuperview()
            })
        })
    }
}
