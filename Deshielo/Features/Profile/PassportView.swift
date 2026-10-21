import SwiftUI

/// Достижение кулинарного паспорта.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Int
    let goal: Int

    var isUnlocked: Bool { progress >= goal }
}

enum Achievements {
    static func all(profile: UserProfile, catalog: Catalog) -> [Achievement] {
        let cooked = Set(profile.cooked.map(\.recipeID)).compactMap { catalog.recipe($0) }
        let passport = PassportSummary(profile: profile, catalog: catalog)

        func count(in collection: String) -> Int {
            cooked.filter { $0.collections.contains(collection) }.count
        }

        return [
            Achievement(id: "first", title: "Первое блюдо", detail: "Приготовить любое блюдо",
                        symbol: "fork.knife", progress: cooked.count, goal: 1),
            Achievement(id: "ten", title: "Десятка", detail: "Приготовить 10 разных блюд",
                        symbol: "10.circle", progress: cooked.count, goal: 10),
            Achievement(id: "traveler", title: "Путешественник", detail: "Блюда пяти стран",
                        symbol: "airplane", progress: passport.countriesCount, goal: 5),
            Achievement(id: "globetrotter", title: "Гурман без границ", detail: "Блюда десяти стран",
                        symbol: "globe", progress: passport.countriesCount, goal: 10),
            Achievement(id: "historian", title: "Историк", detail: "Три рецепта из старинных книг",
                        symbol: "scroll", progress: count(in: "history"), goal: 3),
            Achievement(id: "time-traveler", title: "Машина времени", detail: "Блюда четырёх разных эпох",
                        symbol: "hourglass", progress: passport.eraIDs.count, goal: 4),
            Achievement(id: "star", title: "Звёздный ужин", detail: "Три блюда высокой кухни",
                        symbol: "star", progress: count(in: "star"), goal: 3),
            Achievement(id: "chefs", title: "Школа шефов", detail: "Три блюда великих шефов",
                        symbol: "person.2", progress: count(in: "chefs"), goal: 3),
            Achievement(id: "russian", title: "Русская душа", detail: "Три блюда русской кухни",
                        symbol: "house", progress: cooked.filter { $0.country == "RU" }.count, goal: 3),
            Achievement(id: "unusual", title: "Смелый вкус", detail: "Два необычных рецепта",
                        symbol: "sparkles", progress: count(in: "unusual"), goal: 2)
        ]
    }
}

/// Кулинарный паспорт: штампы стран, эпохи и достижения.
struct PassportView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let passport = PassportSummary(profile: profile.profile, catalog: catalog)
        let usedEras = Set(catalog.datedRecipes.compactMap { catalog.era(for: $0.year)?.id })
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PassportSummaryCard(passport: passport, showsHeader: false)
                    .card()

                SectionHeader(title: "Страны", subtitle: "Штамп ставится, когда вы отмечаете приготовленное блюдо")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 16) {
                    ForEach(catalog.countriesWithRecipes) { country in
                        NavigationLink(value: Route.country(country.code)) {
                            StampView(country: country, date: passport.stamps[country.code])
                        }
                        .buttonStyle(.plain)
                    }
                }

                SectionHeader(title: "Эпохи")
                FlowLayout(spacing: 8) {
                    ForEach(catalog.eras.filter { usedEras.contains($0.id) }) { era in
                        let visited = passport.eraIDs.contains(era.id)
                        Tag(title: era.title,
                            systemImage: visited ? "checkmark.seal.fill" : "seal",
                            tint: visited ? Theme.herb : .secondary)
                    }
                }

                SectionHeader(title: "Достижения")
                VStack(spacing: 12) {
                    ForEach(Achievements.all(profile: profile.profile, catalog: catalog)) { achievement in
                        AchievementRow(achievement: achievement)
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Кулинарный паспорт")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Штамп страны: круглая печать с флагом и датой.
struct StampView: View {
    let country: Country
    let date: Date?

    var body: some View {
        let stamped = date != nil
        let angle = Double(Int(DailyPick.stableHash(country.code) % 17)) - 8
        VStack(spacing: 3) {
            Text(country.flag)
                .font(.system(size: 30))
                .grayscale(stamped ? 0 : 1)
                .opacity(stamped ? 1 : 0.45)
            Text(country.name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            Text(date.map { $0.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)) } ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(stamped ? Theme.accent : Color.secondary)
        .frame(width: 92, height: 92)
        .background {
            Circle()
                .strokeBorder(stamped ? Theme.accent : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: stamped ? [] : [4, 3]))
        }
        .rotationEffect(.degrees(stamped ? angle : 0))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stamped ? "\(country.name): штамп получен" : "\(country.name): пока без штампа")
    }
}

private struct AchievementRow: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(achievement.isUnlocked ? Theme.accent : Theme.surfaceSecondary, in: Circle())
                .foregroundStyle(achievement.isUnlocked ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.headline)
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(min(achievement.progress, achievement.goal)), total: Double(achievement.goal))
                    .tint(achievement.isUnlocked ? Theme.herb : Theme.accent)
            }
            Text("\(min(achievement.progress, achievement.goal))/\(achievement.goal)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
