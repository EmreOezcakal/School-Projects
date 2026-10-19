import UIKit

enum Haptics {
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func shutter() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
