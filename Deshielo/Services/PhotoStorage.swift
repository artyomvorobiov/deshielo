import UIKit

/// Подготовка фото к отправке: не больше 1600 пикселей по длинной стороне, JPEG.
/// Изображение перерисовывается, поэтому метаданные (в том числе геопозиция) не уходят на сервер.
enum ImageCompressor {
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Фото из дневника готовки: JPEG-файлы рядом с профилем. На сервер они не отправляются.
enum JournalPhotos {
    static var folder: URL { AppGroup.containerURL.appendingPathComponent("JournalPhotos", isDirectory: true) }

    /// Сохраняет фото и возвращает имя файла.
    static func save(_ image: UIImage) -> String? {
        guard let data = ImageCompressor.jpegData(from: image, maxDimension: 1600, quality: 0.82) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func url(for name: String) -> URL { folder.appendingPathComponent(name, isDirectory: false) }

    static func image(named name: String) -> UIImage? { UIImage(contentsOfFile: url(for: name).path) }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
