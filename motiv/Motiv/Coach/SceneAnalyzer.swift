import CoreImage
import ImageIO
import Vision

/// Arbeitet auf der Video-Queue der Kamera: findet Motive (Saliency), verfolgt sie
/// von Bild zu Bild (Tracking) und liefert bei Bedarf ein JPEG des aktuellen Sucherbilds.
final class SceneAnalyzer {
    /// Neue Position des verfolgten Motivs in Einheitskoordinaten (Ursprung oben links)
    /// oder nil, wenn es verloren ging. Läuft auf dem Main-Thread; `Int` ist die Tracking-Runde.
    var onTrackUpdate: ((Int, CGRect?) -> Void)?

    private let queue: DispatchQueue
    private let ciContext = CIContext()
    private var sequenceHandler = VNSequenceRequestHandler()
    private var trackRequest: VNTrackObjectRequest?
    private var trackGeneration = 0
    private var lowConfidenceFrames = 0
    private var frameIndex = 0
    private var pendingScan: ((CGRect?) -> Void)?
    private var pendingSnapshot: ((Data?) -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Sucht im nächsten Kamerabild das stärkste Motiv. `completion` läuft auf dem Main-Thread.
    func scan(completion: @escaping (CGRect?) -> Void) {
        queue.async { self.pendingScan = completion }
    }

    /// JPEG des nächsten Kamerabilds (längste Seite höchstens `maxSide` Pixel).
    func snapshotJPEG(completion: @escaping (Data?) -> Void) {
        queue.async { self.pendingSnapshot = completion }
    }

    func startTracking(_ rect: CGRect, generation: Int) {
        queue.async {
            let observation = VNDetectedObjectObservation(boundingBox: rect.flippedY)
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            self.trackRequest = request
            self.trackGeneration = generation
            self.sequenceHandler = VNSequenceRequestHandler()
            self.lowConfidenceFrames = 0
        }
    }

    func stopTracking() {
        queue.async { self.trackRequest = nil }
    }

    /// Wird für jedes Kamerabild auf `queue` aufgerufen.
    func process(_ buffer: CVPixelBuffer) {
        frameIndex += 1

        if let scan = pendingScan {
            pendingScan = nil
            let subject = Self.findSubject(in: buffer)
            DispatchQueue.main.async { scan(subject) }
        }

        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            let data = jpeg(from: buffer, maxSide: 1024)
            DispatchQueue.main.async { snapshot(data) }
        }

        // Jedes zweite Bild verfolgen reicht für eine flüssige Anzeige.
        guard let request = trackRequest, frameIndex % 2 == 0 else { return }
        let generation = trackGeneration
        do {
            try sequenceHandler.perform([request], on: buffer, orientation: .up)
            guard let result = request.results?.first else { return }
            request.inputObservation = result
            lowConfidenceFrames = result.confidence < 0.3 ? lowConfidenceFrames + 1 : 0
            let lost = lowConfidenceFrames > 8
            if lost { trackRequest = nil }
            let rect: CGRect? = lost ? nil : result.boundingBox.flippedY
            DispatchQueue.main.async { self.onTrackUpdate?(generation, rect) }
        } catch {
            trackRequest = nil
            DispatchQueue.main.async { self.onTrackUpdate?(generation, nil) }
        }
    }

    /// Kombiniert aufmerksamkeits- und objektbasierte Saliency und bevorzugt mittelgroße Motive –
    /// ein Detail, das man aus der Szene herausholen kann, statt einfach alles.
    private static func findSubject(in buffer: CVPixelBuffer) -> CGRect? {
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        let objectness = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform([attention, objectness])

        let observations = (attention.results ?? []) + (objectness.results ?? [])
        var best: (rect: CGRect, score: CGFloat)?
        for observation in observations {
            for object in observation.salientObjects ?? [] {
                let box = object.boundingBox
                let area = box.width * box.height
                guard area > 0.01 else { continue }
                let sizeScore = 1 - min(abs(area - 0.2) / 0.5, 1)
                let score = CGFloat(object.confidence) * 0.5 + sizeScore
                if best == nil || score > best!.score {
                    best = (box.flippedY, score)
                }
            }
        }
        return best?.rect
    }

    private func jpeg(from buffer: CVPixelBuffer, maxSide: CGFloat) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return ciContext.jpegRepresentation(
            of: scaled, colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]
        )
    }
}
