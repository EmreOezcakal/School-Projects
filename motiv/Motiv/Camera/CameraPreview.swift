import AVFoundation
import SwiftUI

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass oben garantiert den Typ
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lockPortrait()
    }

    /// Die Vorschau immer im Hochformat zeigen – wie Foto- und Analysebilder.
    func lockPortrait() {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(90),
              connection.videoRotationAngle != 90 else { return }
        connection.videoRotationAngle = 90
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

    // Die Verbindung entsteht erst, wenn die Kamera eingerichtet ist – daher bei jeder Aktualisierung prüfen.
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.lockPortrait()
    }
}
