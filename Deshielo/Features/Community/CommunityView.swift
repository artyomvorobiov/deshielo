import SwiftUI

/// Вкладка «Сообщество»: рецепты пользователей с поиском, сортировкой и категориями.
struct CommunityView: View {
    @Environment(CommunityStore.self) private var community
    @Environment(Router.self) private var router

    @State private var searchText = ""
    @State private var query = CommunityQuery()
    @State private var recipes: [CommunityRecipe] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var editor: RecipeEditorRequest?
    @State private var toast: String?

    private struct LoadKey: Hashable {
        let query: CommunityQuery
        let revision: Int
    }

    var body: some View {
        Group {
            if community.isConfigured {
                feed
            } else {
                CommunityNotConfiguredView()
            }
        }
        .screenBackground()
        .navigationTitle("Сообщество")
        .searchable(text: $searchText, prompt: "Блюдо или продукт")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.communityAccount) {
                    Image(systemName: community.user == nil ? "person.crop.circle" : "person.crop.circle.fill")
                }
                .accessibilityLabel("Аккаунт сообщества")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = RecipeEditorRequest(recipe: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новый рецепт")
                .disabled(!community.isConfigured)
            }
        }
        .task(id: searchText) {
            // Запрос уходит, когда человек перестал печатать.
            guard searchText != query.text else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            query.text = searchText
        }
        .task(id: LoadKey(query: query, revision: community.revision)) {
            guard community.isConfigured else { return }
            await reload()
        }
        .refreshable { await reload() }
        .onAppear(perform: applyPendingSearch)
        .onChange(of: router.communitySearch) { _, _ in applyPendingSearch() }
        .sheet(item: $editor) { _ in
            RecipeEditorView(existing: nil) { recipe in
                toast = recipe.isPublished ? "Рецепт опубликован" : "Черновик сохранён — он виден только вам"
            }
        }
        .toast($toast)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if community.user == nil && query.text.isEmpty {
                    JoinBanner()
                }
                controls
                if recipes.isEmpty {
                    placeholder
                } else {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: Route.communityRecipe(recipe.id)) {
                            CommunityRecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if recipe.id == recipes.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Сортировка", selection: $query.sort) {
                ForEach(CommunitySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "Все", isSelected: query.category == nil) {
                        query.category = nil
                    }
                    ForEach(RecipeCategory.allCases) { category in
                        Chip(title: category.title, systemImage: category.symbol, isSelected: query.category == category) {
                            query.category = query.category == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if let loadError {
            ContentUnavailableView {
                Label("Не удалось загрузить", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Повторить") {
                    Task { await reload() }
                }
            }
        } else if !query.text.isEmpty {
            ContentUnavailableView.search(text: query.text)
        } else {
            ContentUnavailableView {
                Label("Здесь пока пусто", systemImage: "fork.knife")
            } description: {
                Text(query.category == nil
                     ? "Станьте первым — поделитесь любимым рецептом и фото."
                     : "В этой категории пока нет рецептов.")
            } actions: {
                Button("Добавить рецепт") {
                    editor = RecipeEditorRequest(recipe: nil)
                }
            }
        }
    }

    private func applyPendingSearch() {
        guard let pending = router.communitySearch else { return }
        router.communitySearch = nil
        searchText = pending
        query.text = pending
    }

    private func reload() async {
        isLoading = true
        do {
            let result = try await community.recipes(query, page: 1)
            recipes = result.items
            page = 1
            hasMore = result.hasMore
            loadError = nil
        } catch is CancellationError {
            // Запрос сменился — результат уже не нужен.
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        do {
            let next = try await community.recipes(query, page: page + 1)
            let known = Set(recipes.map(\.id))
            recipes += next.items.filter { !known.contains($0.id) }
            page += 1
            hasMore = next.hasMore
        } catch {
            hasMore = false
        }
        isLoading = false
    }
}

/// Приглашение войти, пока человек смотрит ленту без аккаунта.
private struct JoinBanner: View {
    var body: some View {
        NavigationLink(value: Route.communityAccount) {
            HStack(spacing: 14) {
                Image(systemName: "camera.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Делитесь рецептами и фото")
                        .font(.headline)
                    Text("Войдите, чтобы публиковать свои блюда и оценивать чужие")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Карточка рецепта сообщества в ленте.
struct CommunityRecipeCard: View {
    let recipe: CommunityRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommunityRecipeCover(recipe: recipe)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if recipe.photos.count > 1 {
                        Label("\(recipe.photos.count)", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.display(.title3))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    AuthorAvatar(name: recipe.author.name, size: 20)
                    Text(recipe.author.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RatingBadge(rating: recipe.rating)
                    if recipe.totalMinutes > 0 {
                        Label(DurationText.short(minutes: recipe.totalMinutes), systemImage: "clock")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }
}

/// Обложка: первое фото автора или генеративная картинка.
struct CommunityRecipeCover: View {
    let recipe: CommunityRecipe
    var prefersThumbnail = true

    var body: some View {
        if let photo = recipe.photos.first {
            Color.clear
                .overlay {
                    CommunityImage(url: prefersThumbnail ? photo.thumbnailURL : photo.url)
                }
                .clipped()
        } else {
            DishArtwork(recipe: .artworkPlaceholder(id: "community-\(recipe.id)", palette: recipe.palette),
                        showsYear: false)
        }
    }
}
