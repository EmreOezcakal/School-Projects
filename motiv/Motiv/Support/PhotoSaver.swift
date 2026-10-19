import Photos
import UIKit

enum PhotoSaver {
    /// Legt das Bild in der Fotos-App ab. `completion` läuft auf dem Main-Thread.
    static func save(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited,
                  let data = image.jpegData(compressionQuality: 0.95) else {
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
