import CoreMotion
import Foundation

/// Wasserwaage: Neigung des iPhones um die Blickachse.
final class LevelMonitor: ObservableObject {
    /// Positiv, wenn das iPhone im Uhrzeigersinn gedreht ist.
    @Published private(set) var rollDegrees: Double = 0
    @Published private(set) var isLevel = false
    /// Falsch, wenn das iPhone flach liegt – dann ist eine Horizontlinie sinnlos.
    @Published private(set) var isUsable = true

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let roll = atan2(gravity.x, -gravity.y) * 180 / .pi
            let usable = abs(gravity.z) < 0.85 && abs(roll) < 35
            let level = usable && abs(roll) < 1.0
            self.rollDegrees = roll
            if usable != self.isUsable { self.isUsable = usable }
            if level != self.isLevel {
                self.isLevel = level
                if level { Haptics.tick() }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
