import CoreImage
import ImageIO
import UIKit

/// Bearbeitet Fotos verlustarm über Core Image: kein Neuzeichnen als UIImage, voller Farbraum, volle Auflösung.
enum PhotoProcessor {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Liest Fotodaten aufrecht ein (EXIF-Ausrichtung angewendet).
    static func image(from data: Data) -> CIImage? {
        CIImage(data: data, options: [.applyOrientationProperty: true])
    }

    /// Schneidet einen Ausschnitt in Einheitskoordinaten (0…1, Ursprung oben links) aus.
    static func crop(_ image: CIImage, unit r: CGRect) -> CIImage {
        let e = image.extent
        // Core Image zählt y von unten
        let rect = CGRect(x: e.minX + r.minX * e.width, y: e.minY + (1 - r.maxY) * e.height,
                          width: r.width * e.width, height: r.height * e.height)
            .integral
            .intersection(e)
        return image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    /// Kodiert in voller Auflösung als HEIF (kleiner bei gleicher Qualität) oder JPEG (für Windows-PCs).
    static func encode(_ image: CIImage, asJPEG: Bool, quality: CGFloat = 0.92) -> Data? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        if !asJPEG, let heif = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: space, options: options) {
            return heif
        }
        return context.jpegRepresentation(of: image, colorSpace: space, options: options)
    }

    /// Kleines Vorschaubild für Daumen und Editor-Vorschau.
    static func thumbnail(_ image: CIImage, maxSide: CGFloat) -> UIImage? {
        let s = min(1, maxSide / max(image.extent.width, image.extent.height, 1))
        let small = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Breite × Höhe in Megapixeln, z. B. „48 MP“.
    static func megapixels(_ image: CIImage) -> String {
        let mp = image.extent.width * image.extent.height / 1_000_000
        return mp >= 10 ? "\(Int(mp.rounded())) MP" : String(format: "%.1f MP", mp)
    }
}
