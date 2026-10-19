import CoreGraphics

/// Nächster Schritt, damit der gelbe Rahmen das Bildformat füllt.
struct Guidance: Equatable {
    enum Step: Equatable {
        case moveLeft, moveRight, moveUp, moveDown
        case closer(zoom: CGFloat?)
        case back
        case hold
    }

    let step: Step

    var aligned: Bool { step == .hold }

    var text: String {
        switch step {
        case .moveLeft: return "← Schwenk etwas nach links"
        case .moveRight: return "Schwenk etwas nach rechts →"
        case .moveUp: return "↑ Etwas nach oben"
        case .moveDown: return "↓ Etwas nach unten"
        case .closer(let zoom):
            if let zoom { return "Geh näher ran oder tippe auf \(ZoomPreset.label(zoom))" }
            return "Geh näher ran"
        case .back: return "Geh einen Schritt zurück"
        case .hold: return "Perfekt – jetzt auslösen"
        }
    }

    /// `target` und `crop` in Einheitskoordinaten des Sucherbilds.
    static func evaluate(target: CGRect, crop: CGRect, currentZoom: CGFloat,
                         presets: [CGFloat], wasAligned: Bool) -> Guidance {
        // Etwas Spielraum, sobald es einmal gepasst hat – sonst flackert die Anzeige.
        let offsetLimit: CGFloat = wasAligned ? 0.13 : 0.09
        let minScale: CGFloat = wasAligned ? 0.8 : 0.86
        let maxScale: CGFloat = wasAligned ? 1.3 : 1.18

        let dx = (target.midX - crop.midX) / crop.width
        let dy = (target.midY - crop.midY) / crop.height
        let scale = min(crop.width / target.width, crop.height / target.height)

        if max(abs(dx), abs(dy)) > offsetLimit {
            if abs(dx) >= abs(dy) { return Guidance(step: dx < 0 ? .moveLeft : .moveRight) }
            return Guidance(step: dy < 0 ? .moveUp : .moveDown)
        }
        if scale > maxScale {
            let wanted = currentZoom * scale
            let preset = presets.filter { $0 > currentZoom * 1.1 && $0 <= wanted * 1.15 }.max()
            return Guidance(step: .closer(zoom: preset))
        }
        if scale < minScale { return Guidance(step: .back) }
        return Guidance(step: .hold)
    }
}
