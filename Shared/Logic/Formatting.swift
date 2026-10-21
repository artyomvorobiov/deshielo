import Foundation

/// Русские формы множественного числа: 1 рецепт, 2 рецепта, 5 рецептов.
enum RussianPlural {
    static func form(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(count)
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    /// Для дробных чисел используется форма «few»: 1,5 стакана, ½ пучка.
    static func form(_ value: Double, _ one: String, _ few: String, _ many: String) -> String {
        if value.rounded() != value { return few }
        return form(Int(value), one, few, many)
    }

    /// «5 рецептов».
    static func phrase(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count) \(form(count, one, few, many))"
    }
}

/// Единицы измерения ингредиентов.
enum MeasureUnit: String, CaseIterable, Sendable {
    case g, kg, ml, l, pcs, tbsp, tsp, pinch, clove, bunch, sprig, slice, leaf, stalk, head, toTaste

    enum Kind: Sendable { case mass, volume, count, toTaste }

    var kind: Kind {
        switch self {
        case .g, .kg: .mass
        case .ml, .l: .volume
        case .toTaste: .toTaste
        default: .count
        }
    }

    /// Коэффициент к базовой единице: граммы для массы, миллилитры для объёма.
    var baseFactor: Double {
        switch self {
        case .kg, .l: 1000
        default: 1
        }
    }

    /// Название единицы с учётом числа.
    func name(for value: Double) -> String {
        switch self {
        case .g: "г"
        case .kg: "кг"
        case .ml: "мл"
        case .l: "л"
        case .pcs: "шт."
        case .tbsp: "ст. л."
        case .tsp: "ч. л."
        case .toTaste: "по вкусу"
        case .pinch: RussianPlural.form(value, "щепотка", "щепотки", "щепоток")
        case .clove: RussianPlural.form(value, "зубчик", "зубчика", "зубчиков")
        case .bunch: RussianPlural.form(value, "пучок", "пучка", "пучков")
        case .sprig: RussianPlural.form(value, "веточка", "веточки", "веточек")
        case .slice: RussianPlural.form(value, "ломтик", "ломтика", "ломтиков")
        case .leaf: RussianPlural.form(value, "лист", "листа", "листьев")
        case .stalk: RussianPlural.form(value, "стебель", "стебля", "стеблей")
        case .head: RussianPlural.form(value, "головка", "головки", "головок")
        }
    }
}

enum AmountFormatter {
    /// Текст количества: «250 г», «1,2 кг», «1½ шт.», «2 зубчика», «по вкусу».
    /// Масса и объём округляются до «красивых» значений, штучное — до четвертинок.
    static func format(amount: Double?, unit: String?) -> String {
        let measure = unit.flatMap(MeasureUnit.init(rawValue:))
        if measure == .toTaste { return "по вкусу" }
        guard let amount, amount > 0 else {
            return measure == nil ? "" : "по вкусу"
        }
        guard let measure else {
            // Неизвестная единица — показываем как есть.
            return [number(amount, fractions: true), unit ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        switch measure.kind {
        case .mass:
            return metric(amount * measure.baseFactor, small: "г", large: "кг")
        case .volume:
            return metric(amount * measure.baseFactor, small: "мл", large: "л")
        case .count, .toTaste:
            let value = roundedCount(amount)
            return "\(number(value, fractions: true)) \(measure.name(for: value))"
        }
    }

    /// Округление граммов и миллилитров: до 0,5 — для малых количеств, до 5 — для крупных.
    static func metric(_ base: Double, small: String, large: String) -> String {
        if base >= 1000 {
            let value = (base / 1000 * 100).rounded() / 100
            return "\(number(value, fractions: false)) \(large)"
        }
        let value: Double
        switch base {
        case ..<10: value = max(0.5, (base * 2).rounded() / 2)
        case ..<100: value = base.rounded()
        default: value = (base / 5).rounded() * 5
        }
        return "\(number(value, fractions: false)) \(small)"
    }

    /// Округление штучных количеств до четвертинок; крупные — до целых.
    static func roundedCount(_ value: Double) -> Double {
        if value >= 10 { return value.rounded() }
        return max(0.25, (value * 4).rounded() / 4)
    }

    /// Число по-русски: запятая как разделитель, дроби ¼ ½ ¾ для штучного.
    static func number(_ value: Double, fractions: Bool) -> String {
        if fractions {
            let whole = Int(value.rounded(.down))
            let fraction = value - Double(whole)
            let symbol: String?
            switch fraction {
            case 0.2..<0.3: symbol = "¼"
            case 0.45..<0.55: symbol = "½"
            case 0.7..<0.8: symbol = "¾"
            default: symbol = nil
            }
            if let symbol {
                return whole == 0 ? symbol : "\(whole)\(symbol)"
            }
        }
        if value.rounded() == value {
            return String(Int(value))
        }
        let text = String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return text.replacingOccurrences(of: ".", with: ",")
    }
}

enum DurationText {
    /// «45 мин», «1 ч 30 мин», «2 сут.»
    static func short(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        if minutes >= 1440 && minutes % 1440 == 0 {
            return "\(minutes / 1440) сут."
        }
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) мин"
        case (_, 0): return "\(hours) ч"
        default: return "\(hours) ч \(rest) мин"
        }
    }

    /// Время таймера: «4:05» или «1:04:05».
    static func clock(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// «5 минут», «1,5 минуты», «30 секунд» — для подписей таймеров.
    static func timerTitle(minutes: Double) -> String {
        if minutes < 1 {
            let seconds = Int((minutes * 60).rounded())
            return RussianPlural.phrase(seconds, "секунда", "секунды", "секунд")
        }
        if minutes.rounded() == minutes {
            return short(minutes: Int(minutes))
        }
        return "\(AmountFormatter.number(minutes, fractions: false)) \(RussianPlural.form(minutes, "минута", "минуты", "минут"))"
    }
}

enum YearText {
    /// «1390», «ок. 1750 до н. э.» — подпись года для рецепта.
    static func label(for recipe: Recipe) -> String? {
        if let label = recipe.yearLabel { return label }
        guard let year = recipe.year else { return nil }
        return year < 0 ? "\(-year) до н. э." : String(year)
    }

    /// Короткая подпись для шкалы времени.
    static func short(_ year: Int) -> String {
        year < 0 ? "\(-year) до н. э." : String(year)
    }
}

extension Recipe {
    /// Строка происхождения: «🇫🇷 Франция · 1975».
    func originLine(in catalog: Catalog) -> String {
        var parts: [String] = []
        if let country = catalog.country(country) {
            parts.append("\(country.flag) \(country.name)")
        } else if let origin {
            parts.append(origin)
        }
        if let year = YearText.label(for: self) {
            parts.append(year)
        }
        return parts.joined(separator: " · ")
    }

    var servingsText: String {
        RussianPlural.phrase(servings, "порция", "порции", "порций")
    }
}
