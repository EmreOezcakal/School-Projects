import SwiftUI

@main
struct MotivApp: App {
    @StateObject private var camera: CameraModel
    @StateObject private var coach: CoachModel

    init() {
        let camera = CameraModel()
        _camera = StateObject(wrappedValue: camera)
        _coach = StateObject(wrappedValue: CoachModel(analyzer: camera.analyzer))
    }

    var body: some Scene {
        WindowGroup {
            CameraScreen(camera: camera, coach: coach)
                .preferredColorScheme(.dark)
        }
    }
}
