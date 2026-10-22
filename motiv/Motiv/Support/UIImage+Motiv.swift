import CoreImage

/// Bild, das im Editor geöffnet wird – in voller Auflösung, aufrecht.
struct EditableImage: Identifiable {
    let id = UUID()
    let source: CIImage
}
