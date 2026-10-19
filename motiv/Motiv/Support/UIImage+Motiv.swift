import UIKit

extension UIImage {
    /// Zeichnet das Bild neu, sodass die Pixel aufrecht liegen (`imageOrientation == .up`).
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Schneidet einen Ausschnitt in Einheitskoordinaten (0…1, Ursprung oben links) aus.
    func cropped(toUnit rect: CGRect) -> UIImage {
        let upright = normalizedUp()
        guard let cgImage = upright.cgImage else { return upright }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let pixels = CGRect(x: rect.minX * width, y: rect.minY * height,
                            width: rect.width * width, height: rect.height * height)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cropped = cgImage.cropping(to: pixels) else { return upright }
        return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
    }
}

/// Bild, das im Editor geöffnet wird.
struct EditableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
