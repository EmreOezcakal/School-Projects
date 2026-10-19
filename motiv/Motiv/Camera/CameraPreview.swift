import AVFoundation
import SwiftUI

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass oben garantiert den Typ
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// Live-Bild der Kamera. Der umgebende Rahmen hat dasselbe Seitenverhältnis wie der Sensor (3:4),
/// daher zeigt die Vorschau genau das ganze Foto.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
