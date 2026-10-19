import Foundation
import UIKit

/// Verbindet Scan, Tracking und Hinweise: Wo ist das Motiv, und was muss ich tun, damit es das Bild füllt?
final class CoachModel: ObservableObject {
    /// Seitenverhältnis des Kamerabilds im Hochformat (Sensor 4:3).
    static let imageAspect: CGFloat = 3.0 / 4.0

    @Published private(set) var target: CGRect?
    @Published private(set) var guidance: Guidance?
    @Published private(set) var isScanning = false
    @Published private(set) var subject: String?
    @Published private(set) var tip: String?
    @Published private(set) var status: String?

    var aspect: AspectRatio = .portrait9x16
    var currentZoom: CGFloat = 1
    var zoomPresets: [CGFloat] = [1]

    private let analyzer: SceneAnalyzer
    private var generation = 0

    init(analyzer: SceneAnalyzer) {
        self.analyzer = analyzer
        analyzer.onTrackUpdate = { [weak self] generation, rect in
            self?.trackUpdated(generation: generation, rect: rect)
        }
    }

    var crop: CGRect { aspect.unitCrop(imageAspect: Self.imageAspect) }

    // MARK: Scannen

    func scanOnDevice() {
        clearTarget()
        isScanning = true
        analyzer.scan { [weak self] box in
            guard let self else { return }
            self.isScanning = false
            guard let box else {
                self.flash("Kein klares Motiv gefunden – probier einen anderen Blickwinkel")
                return
            }
            self.setTarget(around: box, padding: 1.15)
        }
    }

    func scanWithClaude(apiKey: String, model: String) {
        clearTarget()
        isScanning = true
        let aspect = self.aspect
        analyzer.snapshotJPEG { [weak self] data in
            guard let self else { return }
            guard let data else {
                self.isScanning = false
                self.flash("Kein Kamerabild – versuch's nochmal")
                return
            }
            Task { @MainActor in
                do {
                    let suggestion = try await ClaudeCoach.suggest(jpeg: data, aspect: aspect, apiKey: apiKey, model: model)
                    self.isScanning = false
                    self.setTarget(around: suggestion.unitRect, padding: 1.0)
                    self.subject = suggestion.subject
                    self.tip = suggestion.tip
                } catch {
                    self.isScanning = false
                    self.flash(error.localizedDescription)
                }
            }
        }
    }

    /// Vom Nutzer gezeichneter Rahmen in Einheitskoordinaten.
    func setUserFrame(_ rect: CGRect) {
        clearTarget()
        setTarget(around: rect, padding: 1.0)
    }

    func clearTarget() {
        generation += 1
        analyzer.stopTracking()
        target = nil
        guidance = nil
        subject = nil
        tip = nil
    }

    // MARK: Format & Zoom

    func aspectChanged(_ newAspect: AspectRatio) {
        aspect = newAspect
        if let target {
            let keepSubject = subject
            let keepTip = tip
            setTarget(around: target, padding: 1.0)
            subject = keepSubject
            tip = keepTip
        }
    }

    /// Bei Objektivwechseln springt das Bild – der Tracker würde das Motiv verlieren.
    /// Deshalb wird der Rahmen um die Bildmitte mitskaliert und das Tracking neu gestartet.
    func zoomChanged(from old: CGFloat, to new: CGFloat) {
        currentZoom = new
        guard let current = target, old > 0 else {
            updateGuidance()
            return
        }
        let factor = new / old
        let scaled = CGRect(x: 0.5 + (current.minX - 0.5) * factor,
                            y: 0.5 + (current.minY - 0.5) * factor,
                            width: current.width * factor,
                            height: current.height * factor)
        generation += 1
        let round = generation
        analyzer.stopTracking()
        target = scaled
        updateGuidance()
        // Kurz warten, bis die Kamera den neuen Zoom wirklich liefert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.generation == round else { return }
            let visible = scaled.intersection(.unit)
            guard !visible.isNull, visible.width > 0.05, visible.height > 0.05 else {
                self.clearTarget()
                self.flash("Motiv ist aus dem Bild – tippe nochmal auf ✦")
                return
            }
            self.generation += 1
            self.target = visible
            self.analyzer.startTracking(visible, generation: self.generation)
            self.updateGuidance()
        }
    }

    // MARK: Intern

    func flash(_ message: String) {
        status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.status == message { self?.status = nil }
        }
    }

    private func setTarget(around box: CGRect, padding: CGFloat) {
        let rect = Self.frameTarget(around: box, aspect: aspect.value, imageAspect: Self.imageAspect, padding: padding)
        generation += 1
        subject = nil
        tip = nil
        target = rect
        analyzer.startTracking(rect, generation: generation)
        updateGuidance()
    }

    private func trackUpdated(generation: Int, rect: CGRect?) {
        guard generation == self.generation, target != nil else { return }
        guard let rect else {
            clearTarget()
            flash("Motiv verloren – tippe nochmal auf ✦")
            return
        }
        target = rect
        updateGuidance()
    }

    private func updateGuidance() {
        guard let target else {
            guidance = nil
            return
        }
        let wasAligned = guidance?.aligned ?? false
        let next = Guidance.evaluate(target: target, crop: crop, currentZoom: currentZoom,
                                     presets: zoomPresets, wasAligned: wasAligned)
        if next.aligned && !wasAligned { Haptics.success() }
        if next != guidance { guidance = next }
    }

    /// Erweitert ein Motiv-Rechteck auf das gewählte Format (mit etwas Rand) und hält es im Bild.
    /// Gerechnet wird in einem Raum, in dem das Bild `imageAspect` breit und 1 hoch ist.
    static func frameTarget(around box: CGRect, aspect: CGFloat, imageAspect: CGFloat, padding: CGFloat) -> CGRect {
        var width = box.width * imageAspect * padding
        var height = box.height * padding
        if width / max(height, 0.0001) < aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }
        // Mindestgröße, damit der Tracker genug Bildinhalt hat
        let minWidth = 0.18 * imageAspect
        if width < minWidth {
            height *= minWidth / width
            width = minWidth
        }
        // nicht größer als das Bild
        let shrink = min(imageAspect / width, 1 / height, 1)
        width *= shrink
        height *= shrink

        let centerX = min(max(box.midX * imageAspect, width / 2), imageAspect - width / 2)
        let centerY = min(max(box.midY, height / 2), 1 - height / 2)
        return CGRect(x: (centerX - width / 2) / imageAspect, y: centerY - height / 2,
                      width: width / imageAspect, height: height)
    }
}
