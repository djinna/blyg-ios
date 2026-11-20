import UIKit

/// Turns a picked photo into an upload Studio accepts: JPEG, at most 2048 px on the long side,
/// well under Studio's 5 MiB limit. Re-encoding also drops the photo's location and camera metadata.
nonisolated enum PhotoPrep {
    static let maxDimension: CGFloat = 2048
    static let maxBytes = 5 * 1024 * 1024

    enum Failure: Error { case unreadable, tooLarge }

    static func upload(from data: Data, alt: String) throws -> MediaUpload {
        guard let image = UIImage(data: data) else { throw Failure.unreadable }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return MediaUpload(data: jpeg, filename: "photo.jpg", mimeType: "image/jpeg", alt: alt)
            }
        }
        throw Failure.tooLarge
    }
}
