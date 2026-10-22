import Photos
import UIKit

enum PhotoSaver {
    /// Legt fertige Bilddaten (HEIF oder JPEG) unverändert in der Fotos-App ab. `completion` läuft auf dem Main-Thread.
    static func save(_ data: Data, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { success, _ in
                DispatchQueue.main.async { completion?(success) }
            })
        }
    }
}
