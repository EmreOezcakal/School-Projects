import AVFoundation
import UIKit

/// Eine Zoomstufe, wie sie unter dem Sucher angezeigt wird (.5x, 1x, 2x, 5x …).
struct ZoomPreset: Identifiable, Hashable {
    let display: CGFloat
    var id: CGFloat { display }
    var label: String { Self.label(display) }

    static func label(_ value: CGFloat) -> String {
        let rounded = Double((value * 10).rounded() / 10)
        if rounded < 1 { return ".\(Int((rounded * 10).rounded()))x" }
        if rounded == rounded.rounded() { return "\(Int(rounded))x" }
        return String(format: "%.1fx", rounded)
    }
}

/// Steuert die Rückkamera: Vorschau, Objektiv-/Zoomwahl, Fokus, Blitz und Auslösen.
final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    let analyzer: SceneAnalyzer

    @Published private(set) var isAuthorized = true
    @Published private(set) var zoomPresets: [ZoomPreset] = []
    @Published private(set) var activeZoom: CGFloat = 1
    @Published var flashOn = false
    /// Vorschaubild des letzten Fotos und das Foto selbst in voller Auflösung (HEIF/JPEG).
    @Published var lastPhoto: UIImage?
    var lastPhotoData: Data?

    private let sessionQueue = DispatchQueue(label: "motiv.session")
    private let videoQueue: DispatchQueue
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var captureCompletion: ((Data?) -> Void)?
    /// Größte vom Sensor unterstützte Fotoauflösung und die größte bis 12 MP.
    private var fullDimensions: CMVideoDimensions?
    private var standardDimensions: CMVideoDimensions?

    /// Angezeigter Zoom = Gerätezoom × Faktor. Bei Kameras mit Ultraweitwinkel ist 1.0 Gerätezoom = .5x.
    private var displayMultiplier: CGFloat = 1
    private var minDisplayZoom: CGFloat = 1
    private var maxDisplayZoom: CGFloat = 10

    override init() {
        let queue = DispatchQueue(label: "motiv.video", qos: .userInitiated)
        videoQueue = queue
        analyzer = SceneAnalyzer(queue: queue)
        super.init()
    }

    // MARK: Start / Stopp

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.run()
                } else {
                    DispatchQueue.main.async { self.isAuthorized = false }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func run() {
        sessionQueue.async {
            if !self.isConfigured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices
        for type in types {
            if let device = devices.first(where: { $0.deviceType == type }) { return device }
        }
        return nil
    }

    private func configure() {
        guard let device = Self.bestBackCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Für die Bildanalyse reichen Bilder in Vorschaugröße.
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            if let connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        session.commitConfiguration()
        // erst nach dem Festlegen des Formats: welche Fotoauflösungen der Sensor kann
        configurePhotoDimensions(for: device)

        self.device = device
        isConfigured = true

        let ultraWideTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera]
        let multiplier: CGFloat = ultraWideTypes.contains(device.deviceType) ? 0.5 : 1
        var displays: [CGFloat] = multiplier < 1 ? [0.5, 1, 2] : [1, 2]
        if let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.last {
            let tele = (CGFloat(truncating: switchOver) * multiplier).rounded()
            if tele > 2.5 { displays.append(tele) }
        }
        let maxDisplay = min(device.maxAvailableVideoZoomFactor * multiplier, 15)
        let minDisplay = device.minAvailableVideoZoomFactor * multiplier
        let presets = displays.filter { $0 <= maxDisplay + 0.01 }.map { ZoomPreset(display: $0) }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(1 / multiplier, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {}
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange),
                                               name: AVCaptureDevice.subjectAreaDidChangeNotification, object: device)

        DispatchQueue.main.async {
            self.displayMultiplier = multiplier
            self.minDisplayZoom = minDisplay
            self.maxDisplayZoom = maxDisplay
            self.zoomPresets = presets
            self.activeZoom = 1
        }
    }

    // MARK: Zoom & Fokus

    /// Setzt den angezeigten Zoom (z. B. 0.5, 1, 2, 5). Aufruf vom Main-Thread.
    func setZoom(_ display: CGFloat, animated: Bool) {
        let clamped = min(max(display, minDisplayZoom), maxDisplayZoom)
        activeZoom = clamped
        let factor = clamped / displayMultiplier
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                let value = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if animated {
                    device.ramp(toVideoZoomFactor: value, withRate: 6)
                } else {
                    device.videoZoomFactor = value
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// Fokus und Belichtung auf einen Punkt in Gerätekoordinaten (0…1, Querformat).
    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    @objc private func subjectAreaDidChange() {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Auslösen

    /// Nimmt ein Foto auf und liefert die unveränderten Dateidaten der Kamera (HEIF, mit Metadaten).
    /// `highResolution`: größte Sensorauflösung (24/48 MP, je nach iPhone) statt 12 MP. `completion` läuft auf dem Main-Thread.
    func capturePhoto(highResolution: Bool, completion: @escaping (Data?) -> Void) {
        let flash = flashOn
        sessionQueue.async {
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if self.photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = flash ? .on : .off
            }
            if let dims = highResolution ? self.fullDimensions : self.standardDimensions {
                settings.maxPhotoDimensions = dims
            }
            // Volle Bildverarbeitung von Apple (Deep Fusion / Photonic Engine), etwas langsamer als „balanced“
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Wählt aus den Auflösungen des aktiven Formats die größte und die größte bis 12 MP.
    private func configurePhotoDimensions(for device: AVCaptureDevice) {
        let area = { (d: CMVideoDimensions) in Int(d.width) * Int(d.height) }
        let all = device.activeFormat.supportedMaxPhotoDimensions.sorted { area($0) < area($1) }
        guard let largest = all.last else { return }
        fullDimensions = largest
        standardDimensions = all.last(where: { area($0) <= 12_500_000 }) ?? all.first
        photoOutput.maxPhotoDimensions = largest
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyzer.process(buffer)
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        let completion = captureCompletion
        captureCompletion = nil
        DispatchQueue.main.async { completion?(data) }
    }
}
