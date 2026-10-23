import SwiftUI

/// Рецепт сообщества: фото автора, ингредиенты с пересчётом порций, шаги с таймерами и отзывы.
struct CommunityRecipeView: View {
    let id: String

    @Environment(\.catalog) private var catalog
    @Environment(CommunityStore.self) private var community
    @Environment(ProfileStore.self) private var profile
    @Environment(ShoppingStore.self) private var shopping
    @Environment(TimerCenter.self) private var timers
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var recipe: CommunityRecipe?
    @State private var loadError: String?
    @State private var servings: Int?
    @State private var checked: Set<Int> = []
    @State private var activeTerm: GlossaryTerm?
    @State private var editor: RecipeEditorRequest?
    @State private var reporting: ReportTarget?
    @State private var viewer: PhotoViewerItem?
    @State private var confirmsDelete = false
    @State private var confirmsBlock = false
    @State private var toast: String?

    var body: some View {
        Group {
            if let recipe {
                content(recipe)
            } else if let loadError {
                ContentUnavailableView("Не удалось открыть рецепт", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenBackground()
        .navigationTitle(recipe?.title ?? "Рецепт")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: community.revision) { await load() }
        .sheet(item: $activeTerm) { term in
            TermSheet(term: term)
        }
        .sheet(item: $editor) { request in
            RecipeEditorView(existing: request.recipe) { saved in
                recipe = saved
                toast = "Изменения сохранены"
            }
        }
        .sheet(item: $reporting) { target in
            ReportSheet(target: target) { toast = "Жалоба отправлена. Спасибо!" }
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(url: item.url)
        }
        .confirmationDialog("Удалить рецепт?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить рецепт", role: .destructive, action: deleteRecipe)
        } message: {
            Text("Вместе с ним исчезнут фото и отзывы.")
        }
        .confirmationDialog("Скрыть автора?", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("Скрыть рецепты и отзывы автора", role: .destructive, action: blockAuthor)
        } message: {
            Text("Вернуть автора можно в разделе «Аккаунт».")
        }
        .toast($toast)
    }

    private func content(_ recipe: CommunityRecipe) -> some View {
        let converted = recipe.asRecipe(catalog: catalog)
        let isMine = community.isMine(recipe.author)
        let servingsBinding = Binding(get: { servings ?? recipe.servings }, set: { servings = $0 })
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                gallery(recipe)
                header(recipe, isMine: isMine)
                if !recipe.story.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "О блюде")
                        Text(recipe.story)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                IngredientsSection(recipe: converted, servings: servingsBinding, checked: $checked) {
                    let scale = Double(servingsBinding.wrappedValue) / Double(converted.servings)
                    let count = shopping.add(recipe: converted, scale: scale, catalog: catalog,
                                             includeStaples: profile.includeStaples)
                    toast = "В покупках: +\(RussianPlural.phrase(count, "продукт", "продукта", "продуктов"))"
                }
                StepsSection(recipe: converted, onTerm: { activeTerm = $0 }) { step, index in
                    guard let minutes = step.timer else { return }
                    let label = step.title ?? "Шаг \(index + 1)"
                    timers.start(label: label, minutes: minutes, recipe: converted)
                    toast = "Таймер «\(label)» на \(DurationText.timerTitle(minutes: minutes))"
                }
                ReviewsSection(target: .community(recipe.id), recipeTitle: recipe.title, summary: recipe.rating,
                               allowsReview: !isMine) { toast = $0 }
                Text("Рецепт опубликовал участник сообщества — редакция Deshielo его не проверяла. Калорийность не указана.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                router.startCooking(converted, servings: servingsBinding.wrappedValue)
            } label: {
                Label("Начать готовить", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText(recipe)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    if isMine {
                        Button("Редактировать", systemImage: "pencil") {
                            editor = RecipeEditorRequest(recipe: recipe)
                        }
                        Button("Удалить рецепт", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                    } else {
                        Button("Пожаловаться", systemImage: "exclamationmark.bubble") {
                            reporting = .recipe(recipe.id)
                        }
                        Button("Скрыть автора", systemImage: "eye.slash") {
                            confirmsBlock = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ещё")
            }
        }
    }

    @ViewBuilder
    private func gallery(_ recipe: CommunityRecipe) -> some View {
        Group {
            if recipe.photos.count > 1 {
                TabView {
                    ForEach(recipe.photos) { photo in
                        Button {
                            viewer = PhotoViewerItem(url: photo.url)
                        } label: {
                            Color.clear
                                .overlay { CommunityImage(url: photo.url) }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else if let photo = recipe.photos.first {
                Button {
                    viewer = PhotoViewerItem(url: photo.url)
                } label: {
                    CommunityRecipeCover(recipe: recipe, prefersThumbnail: false)
                }
                .buttonStyle(.plain)
            } else {
                CommunityRecipeCover(recipe: recipe)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("Фото блюда")
    }

    private func header(_ recipe: CommunityRecipe, isMine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isMine && (recipe.isHidden || !recipe.isPublished) {
                Label(recipe.isHidden
                      ? "Рецепт скрыт модератором после жалоб. Напишите модератору, если это ошибка."
                      : "Черновик: рецепт видите только вы. Опубликуйте его в редакторе.",
                      systemImage: recipe.isHidden ? "eye.slash" : "pencil")
                    .font(.subheadline)
                    .foregroundStyle(recipe.isHidden ? Color.red : Color.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow(recipe).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(recipe.title)
                    .font(.display(.largeTitle, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                AuthorAvatar(name: recipe.author.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMine ? "\(recipe.author.name) (вы)" : recipe.author.name)
                        .font(.subheadline.weight(.semibold))
                    Text(recipe.created.relativeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if recipe.rating.count > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        RatingStars(value: recipe.rating.average)
                        Text(RatingText.summary(recipe.rating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 0) {
                MetaCell(value: recipe.totalMinutes > 0 ? DurationText.short(minutes: recipe.totalMinutes) : "—",
                         caption: "время")
                Divider().frame(height: 32)
                MetaCell(value: ["Просто", "Средне", "Сложно"][min(max(recipe.difficulty, 1), 3) - 1],
                         caption: "сложность")
                Divider().frame(height: 32)
                MetaCell(value: "\(recipe.servings)",
                         caption: RussianPlural.form(recipe.servings, "порция", "порции", "порций"))
            }
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func eyebrow(_ recipe: CommunityRecipe) -> String {
        var parts = ["Рецепт сообщества", recipe.category.title]
        if let country = catalog.country(recipe.country) {
            parts.insert("\(country.flag) \(country.name)", at: 1)
        }
        return parts.joined(separator: " · ")
    }

    private func shareText(_ recipe: CommunityRecipe) -> String {
        var lines = [recipe.title]
        if !recipe.summary.isEmpty { lines.append(recipe.summary) }
        lines.append("")
        lines.append("Ингредиенты (\(RussianPlural.phrase(recipe.servings, "порция", "порции", "порций"))):")
        for item in recipe.ingredients {
            let amount = AmountFormatter.format(amount: item.amount, unit: item.unit)
            lines.append(amount.isEmpty ? "• \(item.name)" : "• \(item.name) — \(amount)")
        }
        lines.append("")
        lines.append("Рецепт \(recipe.author.name) в приложении Deshielo: \(DeepLink.communityRecipe(recipe.id).url.absoluteString)")
        return lines.joined(separator: "\n")
    }

    private func load() async {
        if recipe == nil {
            recipe = community.cachedRecipe(id)
        }
        do {
            recipe = try await community.recipe(id: id)
            loadError = nil
        } catch is CancellationError {
            // Экран закрыли.
        } catch CommunityError.notFound {
            recipe = nil
            loadError = "Рецепт удалён или скрыт."
        } catch {
            if recipe == nil {
                loadError = error.localizedDescription
            }
        }
    }

    private func deleteRecipe() {
        Task {
            do {
                try await community.deleteRecipe(id: id)
                dismiss()
            } catch {
                toast = error.localizedDescription
            }
        }
    }

    private func blockAuthor() {
        guard let recipe else { return }
        community.block(recipe.author)
        dismiss()
    }
}
