import CoreGraphics

/// Bildformate im Hochformat.
enum AspectRatio: String, CaseIterable, Identifiable {
    case portrait9x16 = "9:16"
    case portrait3x4 = "3:4"
    case portrait4x5 = "4:5"
    case square = "1:1"

    var id: String { rawValue }

    /// Breite geteilt durch Höhe.
    var value: CGFloat {
        switch self {
        case .portrait9x16: return 9.0 / 16.0
        case .portrait3x4: return 3.0 / 4.0
        case .portrait4x5: return 4.0 / 5.0
        case .square: return 1.0
        }
    }

    /// Größtes zentriertes Rechteck in diesem Format innerhalb eines Bildes mit dem
    /// Seitenverhältnis `imageAspect`, in Einheitskoordinaten (0…1, Ursprung oben links).
    func unitCrop(imageAspect: CGFloat) -> CGRect {
        if value < imageAspect {
            let width = value / imageAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            let height = imageAspect / value
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }
}

extension CGRect {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Wechselt zwischen Vision-Koordinaten (Ursprung unten links) und
    /// Einheitskoordinaten mit Ursprung oben links.
    var flippedY: CGRect {
        CGRect(x: minX, y: 1 - maxY, width: width, height: height)
    }

    /// Einheitskoordinaten → Punkte in einer Fläche der Größe `size`.
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width, y: minY * size.height,
               width: width * size.width, height: height * size.height)
    }
}
