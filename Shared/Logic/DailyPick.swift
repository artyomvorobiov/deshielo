import Foundation

/// Рецепт и факт дня. Выбор детерминированный: приложение и виджет показывают одно и то же,
/// а за полный цикл каждый рецепт выпадает ровно один раз.
enum DailyPick {
    static func recipe(for date: Date = .now, in catalog: Catalog, calendar: Calendar = .current) -> Recipe? {
        pick(from: catalog.recipes, id: \.id, date: date, calendar: calendar)
    }

    static func fact(for date: Date = .now, in catalog: Catalog, calendar: Calendar = .current) -> FoodFact? {
        pick(from: catalog.facts, id: \.id, date: date, calendar: calendar)
    }

    /// Номер дня от 1 января 2024 года.
    static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let reference = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 1_704_067_200)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days
    }

    /// Стабильный хэш строки (FNV-1a). В отличие от `hashValue`, не меняется между запусками.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func pick<T>(from items: [T], id: KeyPath<T, String>, date: Date, calendar: Calendar) -> T? {
        guard !items.isEmpty else { return nil }
        let ordered = items.sorted { stableHash($0[keyPath: id]) < stableHash($1[keyPath: id]) }
        let day = dayNumber(for: date, calendar: calendar)
        let index = ((day % ordered.count) + ordered.count) % ordered.count
        return ordered[index]
    }
}

/// Детерминированный генератор случайных чисел (SplitMix64) — для генеративных обложек.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    init(string: String) {
        self.init(seed: DailyPick.stableHash(string))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double.random(in: 0..<1, using: &self)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }
}

/// Ключ дня для меню на неделю: «2026-10-21».
enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
