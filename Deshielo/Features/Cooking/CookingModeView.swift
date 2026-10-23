import SwiftUI
import UIKit

/// Режим готовки: крупный текст, экран не гаснет, таймеры, озвучка шагов голосом.
struct CookingModeView: View {
    let recipe: Recipe
    let servings: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.catalog) private var catalog
    @Environment(TimerCenter.self) private var timers
    @Environment(ProfileStore.self) private var profile
    @Environment(CommunityStore.self) private var community

    @State private var index = 0
    @State private var speech = SpeechReader()
    @State private var showsIngredients = false
    @State private var activeTerm: GlossaryTerm?
    @State private var rating = 0
    @State private var saved = false
    @State private var showsCookedSheet = false
    @State private var status: String?

    private var stepCount: Int { recipe.steps.count }
    private var isFinishPage: Bool { index >= stepCount }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !timers.timers.isEmpty {
                timersStrip
            }
            TabView(selection: $index) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { item in
                    CookingStepPage(step: item.element, number: item.offset + 1, total: stepCount,
                                    recipe: recipe, onTerm: { activeTerm = $0 })
                        .tag(item.offset)
                }
                finishPage
                    .tag(stepCount)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if profile.speakSteps { speakCurrent() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speech.stop()
        }
        .onChange(of: index) { _, _ in
            if profile.speakSteps { speakCurrent() } else { speech.stop() }
        }
        .sensoryFeedback(.selection, trigger: index)
        .sheet(isPresented: $showsIngredients) {
            CookingIngredientsSheet(recipe: recipe, servings: servings)
        }
        .sheet(item: $activeTerm) { term in
            TermSheet(term: term)
        }
        .sheet(isPresented: $showsCookedSheet) {
            CookedSheet(recipe: recipe, initialRating: rating) { result in
                status = CookedRecorder.record(result, recipe: recipe, profile: profile, catalog: catalog)
                saved = true
                Task {
                    if let message = await CookedRecorder.publish(result, recipe: recipe, community: community) {
                        status = message
                    }
                }
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Theme.surfaceSecondary, in: Circle())
                }
                .accessibilityLabel("Закрыть режим готовки")
                Spacer()
                VStack(spacing: 2) {
                    Text(recipe.title)
                        .font(.display(.headline))
                        .lineLimit(1)
                    Text(isFinishPage ? "Готово!" : "Шаг \(index + 1) из \(stepCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showsIngredients = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Theme.surfaceSecondary, in: Circle())
                }
                .accessibilityLabel("Ингредиенты")
            }
            ProgressView(value: Double(min(index + 1, stepCount)), total: Double(max(stepCount, 1)))
                .tint(Theme.accent)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var timersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timers.timers) { timer in
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                        Text(timer.label)
                            .lineLimit(1)
                        Text(timerInterval: timer.startDate...timer.endDate, countsDown: true)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                        Button {
                            timers.cancel(timer)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Остановить таймер")
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(Theme.surfaceSecondary, in: Circle())
            }
            .disabled(index == 0)
            .accessibilityLabel("Предыдущий шаг")

            Button {
                if speech.isSpeaking { speech.stop() } else { speakCurrent() }
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(Theme.surfaceSecondary, in: Circle())
            }
            .disabled(isFinishPage)
            .accessibilityLabel("Прочитать шаг вслух")

            Button {
                withAnimation { index = min(stepCount, index + 1) }
            } label: {
                Text(index >= stepCount - 1 ? "Завершить" : "Дальше")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .opacity(isFinishPage ? 0 : 1)
            .disabled(isFinishPage)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var finishPage: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.herb)
                .symbolEffect(.bounce, value: saved)
            Text("Приятного аппетита!")
                .font(.display(.largeTitle, weight: .bold))
                .multilineTextAlignment(.center)
            if recipe.communityID == nil, let country = catalog.country(recipe.country) {
                Text("Отметьте блюдо — и в кулинарном паспорте появится штамп \(country.flag) \(country.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        rating = value
                    } label: {
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(Theme.gold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) из 5")
                }
            }
            Button {
                if saved {
                    dismiss()
                } else {
                    showsCookedSheet = true
                }
            } label: {
                Text(saved ? "Записано — закрыть" : "Записать в дневник")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(saved ? Theme.herb : Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            if let status {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func speakCurrent() {
        guard index < stepCount else { return }
        let step = recipe.steps[index]
        let intro = "Шаг \(index + 1). " + (step.title.map { "\($0). " } ?? "")
        speech.speak(intro + step.text)
    }
}

/// Страница одного шага: крупный текст, таймер, температура, техники.
private struct CookingStepPage: View {
    let step: RecipeStep
    let number: Int
    let total: Int
    let recipe: Recipe
    let onTerm: (GlossaryTerm) -> Void

    @Environment(\.catalog) private var catalog
    @Environment(TimerCenter.self) private var timers

    private var label: String { step.title ?? "Шаг \(number)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: StepIcon.symbol(for: step))
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text("Шаг \(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let title = step.title {
                    Text(title)
                        .font(.display(.title, weight: .bold))
                }
                Text(step.text)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                if let temperature = step.temperature {
                    Label("\(temperature) °C", systemImage: "thermometer")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let minutes = step.timer {
                    timerBlock(minutes: minutes)
                }
                let terms = step.techniques.compactMap { catalog.term($0) }
                if !terms.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(terms) { term in
                            Button {
                                onTerm(term)
                            } label: {
                                Tag(title: term.term, systemImage: "book.closed", tint: Theme.gold)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    @ViewBuilder
    private func timerBlock(minutes: Double) -> some View {
        if let running = timers.timer(label: label, recipeID: recipe.id) {
            HStack {
                Text(timerInterval: running.startDate...running.endDate, countsDown: true)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Стоп", role: .destructive) {
                    timers.cancel(running)
                }
                .buttonStyle(.bordered)
            }
            .padding(18)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Button {
                timers.start(label: label, minutes: minutes, recipe: recipe)
            } label: {
                Label("Запустить таймер · \(DurationText.timerTitle(minutes: minutes))", systemImage: "timer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Ингредиенты в режиме готовки (с учётом выбранных порций).
private struct CookingIngredientsSheet: View {
    let recipe: Recipe
    let servings: Int

    @Environment(\.catalog) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(recipe.ingredientGroups.enumerated()), id: \.offset) { group in
                    Section(group.element.title ?? RussianPlural.phrase(servings, "порция", "порции", "порций")) {
                        ForEach(group.element.items, id: \.index) { item in
                            IngredientLine(ingredient: item.ingredient,
                                           scale: Double(servings) / Double(recipe.servings),
                                           emoji: catalog.pantryItem(item.ingredient.key)?.emoji,
                                           isChecked: checked.contains(item.index)) {
                                if checked.contains(item.index) {
                                    checked.remove(item.index)
                                } else {
                                    checked.insert(item.index)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ингредиенты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
