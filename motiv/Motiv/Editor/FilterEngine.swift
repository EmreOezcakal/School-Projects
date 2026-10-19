import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct EditSettings: Equatable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var fade: Double = 0
    var vignette: Double = 0
    var grain: Double = 0
}

enum Adjustment: String, CaseIterable, Identifiable {
    case exposure, contrast, saturation, warmth, highlights, shadows, fade, vignette, grain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exposure: return "Belichtung"
        case .contrast: return "Kontrast"
        case .saturation: return "Sättigung"
        case .warmth: return "Wärme"
        case .highlights: return "Lichter"
        case .shadows: return "Tiefen"
        case .fade: return "Verblassen"
        case .vignette: return "Vignette"
        case .grain: return "Körnung"
        }
    }

    var symbol: String {
        switch self {
        case .exposure: return "plusminus.circle"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop"
        case .warmth: return "thermometer.medium"
        case .highlights: return "sun.max"
        case .shadows: return "moon"
        case .fade: return "cloud.fog"
        case .vignette: return "circle.dashed"
        case .grain: return "circle.grid.3x3"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .fade, .vignette, .grain: return 0...1
        default: return -1...1
        }
    }

    var keyPath: WritableKeyPath<EditSettings, Double> {
        switch self {
        case .exposure: return \.exposure
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .warmth: return \.warmth
        case .highlights: return \.highlights
        case .shadows: return \.shadows
        case .fade: return \.fade
        case .vignette: return \.vignette
        case .grain: return \.grain
        }
    }
}

/// Eigene Looks – angelehnt an Analogfilm, aber selbst abgestimmt.
struct FilmPreset: Identifiable {
    let name: String
    let settings: EditSettings
    var id: String { name }

    static let all: [FilmPreset] = [
        FilmPreset(name: "Original", settings: EditSettings()),
        FilmPreset(name: "Sonnig", settings: EditSettings(exposure: 0.1, contrast: 0.15, saturation: 0.15, warmth: 0.5)),
        FilmPreset(name: "Film 400", settings: EditSettings(contrast: -0.1, saturation: -0.1, warmth: 0.25,
                                                            shadows: 0.3, fade: 0.3, grain: 0.35)),
        FilmPreset(name: "Golden", settings: EditSettings(exposure: 0.05, saturation: 0.1, warmth: 0.7,
                                                          highlights: -0.3, vignette: 0.35)),
        FilmPreset(name: "Urlaub", settings: EditSettings(contrast: 0.15, saturation: 0.35, warmth: 0.15)),
        FilmPreset(name: "Kühl", settings: EditSettings(contrast: 0.15, saturation: -0.15, warmth: -0.45)),
        FilmPreset(name: "Matt", settings: EditSettings(contrast: -0.25, saturation: -0.2, shadows: 0.2, fade: 0.5)),
        FilmPreset(name: "S/W Kontrast", settings: EditSettings(contrast: 0.5, saturation: -1, grain: 0.25)),
        FilmPreset(name: "S/W Weich", settings: EditSettings(contrast: -0.1, saturation: -1, fade: 0.35)),
    ]
}

enum FilterEngine {
    static let context = CIContext()

    static func apply(_ settings: EditSettings, to input: CIImage) -> CIImage {
        let extent = input.extent
        var image = input

        if settings.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(settings.exposure)
            image = filter.outputImage ?? image
        }

        if settings.contrast != 0 || settings.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + settings.contrast * 0.35)
            filter.saturation = Float(max(0, 1 + settings.saturation))
            filter.brightness = 0
            image = filter.outputImage ?? image
        }

        if settings.warmth != 0 {
            // Wärmer: mehr Rot, weniger Blau – und umgekehrt.
            let amount = CGFloat(settings.warmth) * 0.12
            let filter = CIFilter.colorMatrix()
            filter.inputImage = image
            filter.rVector = CIVector(x: 1 + amount, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: 1 + amount * 0.2, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: 1 - amount, w: 0)
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            image = filter.outputImage ?? image
        }

        if settings.highlights != 0 || settings.shadows != 0 || settings.fade != 0 {
            let lift = CGFloat(settings.fade) * 0.15
            let filter = CIFilter.toneCurve()
            filter.inputImage = image
            filter.point0 = CGPoint(x: 0, y: lift)
            filter.point1 = CGPoint(x: 0.25, y: 0.25 + CGFloat(settings.shadows) * 0.1 + lift * 0.5)
            filter.point2 = CGPoint(x: 0.5, y: 0.5)
            filter.point3 = CGPoint(x: 0.75, y: 0.75 + CGFloat(settings.highlights) * 0.1)
            filter.point4 = CGPoint(x: 1, y: 1 - CGFloat(settings.fade) * 0.05)
            image = filter.outputImage ?? image
        }

        if settings.vignette > 0 {
            let filter = CIFilter.vignette()
            filter.inputImage = image
            filter.intensity = Float(settings.vignette * 1.5)
            filter.radius = 1.5
            image = filter.outputImage ?? image
        }

        if settings.grain > 0, let noise = CIFilter.randomGenerator().outputImage {
            // Graues Rauschen, sanft per „Weiches Licht“ über das Bild gelegt
            let grayNoise = CIFilter.colorMatrix()
            grayNoise.inputImage = noise.transformed(by: CGAffineTransform(scaleX: 1.5, y: 1.5)).cropped(to: extent)
            grayNoise.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            grayNoise.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            grayNoise.bVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            grayNoise.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            grayNoise.biasVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(settings.grain) * 0.35)
            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = grayNoise.outputImage
            blend.backgroundImage = image
            image = blend.outputImage ?? image
        }

        return image.cropped(to: extent)
    }

    static func render(_ settings: EditSettings, source: CIImage) -> UIImage? {
        let output = apply(settings, to: source)
        guard let cgImage = context.createCGImage(output, from: source.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
