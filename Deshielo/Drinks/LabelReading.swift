import Foundation
import ImageIO
import UIKit
import Vision

/// Поиск вина в Vivino. Открытого API у Vivino нет, поэтому приложение открывает их поиск
/// (сайт или приложение Vivino, если оно установлено). Рейтинги и цены Vivino в Deshielo не показываются.
enum VivinoLink {
    static func search(_ query: String) -> URL? {
        guard let text = query.nilIfBlank,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
        else { return nil }
        return URL(string: "https://www.vivino.com/search/wines?q=\(encoded)")
    }
}

/// Разбор текста, распознанного на этикетке: что похоже на название, а что — служебные надписи.
enum LabelTextParser {
    /// Строка текста и её высота на фото (доля высоты кадра): крупные надписи обычно и есть название.
    struct Line: Hashable, Sendable {
        let text: String
        let height: Double
    }

    struct Result: Hashable, Sendable {
        /// Варианты названия — от самой крупной надписи.
        let suggestions: [String]
        let vintage: Int?

        /// Запрос для поиска: две самые крупные надписи (обычно производитель и вино).
        var query: String { suggestions.prefix(2).joined(separator: " ") }

        static let empty = Result(suggestions: [], vintage: nil)
    }

    /// Служебные надписи: объём, крепость, «содержит сульфиты», адреса, штрихкоды.
    private static let noise: [String] = [
        #"\b\d+([.,]\d+)?\s?(ml|мл|cl|l|л|литр)\b"#,
        #"\d+([.,]\d+)?\s?%"#,
        #"\b(vol|alc|об\.?)\b"#,
        #"sulfit|sulphit|сульфит|contains|contient|enthält|contiene|содержит"#,
        #"product of|produce of|produit de|prodotto|producto de|imported|импорт|изготовител|произведено"#,
        #"mis en bouteille|bottled|imbottigliato|embotellado|abgefüllt|разлит"#,
        #"www\.|https?:|@|\.com\b|\.ru\b"#,
        #"\d{6,}"#
    ]

    static func parse(_ lines: [Line], currentYear: Int = Calendar.current.component(.year, from: .now)) -> Result {
        var vintage: Int?
        var candidates: [(text: String, height: Double)] = []
        for line in lines {
            let text = line.text
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if vintage == nil, let year = year(in: text, upTo: currentYear) {
                vintage = year
            }
            let lowered = text.lowercased()
            let letters = text.filter(\.isLetter).count
            guard letters >= 3,
                  !noise.contains(where: { lowered.range(of: $0, options: .regularExpression) != nil })
            else { continue }
            // Год отдельно не нужен в названии: «Rioja Reserva 2018» → «Rioja Reserva».
            let name = text
                .replacingOccurrences(of: #"\b(19|20)\d{2}\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard name.filter(\.isLetter).count >= 3 else { continue }
            candidates.append((text: prettified(name), height: line.height))
        }
        var seen: Set<String> = []
        let suggestions = candidates
            .sorted { $0.height > $1.height }
            .map(\.text)
            .filter { seen.insert($0.searchNormalized).inserted }
        return Result(suggestions: Array(suggestions.prefix(4)), vintage: vintage)
    }

    /// Урожай: четыре цифры от 1950 года до текущего.
    static func year(in text: String, upTo currentYear: Int) -> Int? {
        guard let range = text.range(of: #"\b(19[5-9]\d|20\d{2})\b"#, options: .regularExpression),
              let year = Int(text[range]), year <= currentYear else { return nil }
        return year
    }

    /// «CHÂTEAU MARGAUX» → «Château Margaux». Надписи в обычном регистре не трогаем.
    static func prettified(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard letters.count > 3, letters == letters.uppercased() else { return text }
        return text.lowercased().capitalized(with: Locale(identifier: "fr_FR"))
    }
}

/// Распознавание текста на фото этикетки прямо на устройстве (Vision) — фото никуда не отправляется.
enum LabelReader {
    /// Языки этикеток: французский, итальянский, испанский, немецкий, португальский, английский и русский.
    private static let languages = ["fr-FR", "it-IT", "es-ES", "de-DE", "pt-BR", "en-US", "ru-RU"]

    static func read(_ image: UIImage) async -> LabelTextParser.Result {
        guard let cgImage = image.cgImage else { return .empty }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines = await Task.detached(priority: .userInitiated) {
            LabelReader.recognize(cgImage, orientation: orientation)
        }.value
        return LabelTextParser.parse(lines)
    }

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [LabelTextParser.Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Названия вин — имена собственные: автокоррекция их только портит.
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = languages.filter { supported.contains($0) }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            return LabelTextParser.Line(text: candidate.string, height: Double(observation.boundingBox.height))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
