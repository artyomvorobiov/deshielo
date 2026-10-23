import SwiftUI

/// Вход и регистрация в сообществе.
struct CommunityAuthForm: View {
    var reason: String?

    @Environment(CommunityStore.self) private var community
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptsRules = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = true
    @State private var showsRules = false

    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp

        var id: String { rawValue }
        var title: String { self == .signIn ? "Вход" : "Регистрация" }
    }

    var body: some View {
        Form {
            Section {
                Picker("Режим", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                if let reason {
                    Text(reason)
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }

            Section {
                if mode == .signUp {
                    TextField("Имя или ник", text: $name)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                }
                TextField("Почта", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            } footer: {
                if mode == .signUp {
                    Text("Пароль — не короче 8 символов. Имя увидят другие участники, почту — никто.")
                }
            }

            if mode == .signUp {
                Section {
                    Toggle("Принимаю правила сообщества", isOn: $acceptsRules)
                    Button("Прочитать правила") { showsRules = true }
                } footer: {
                    Text("В сообществе нет места оскорблениям, спаму и чужим фото без разрешения.")
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(mode == .signIn ? "Войти" : "Создать аккаунт")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isWorking)
                if mode == .signIn {
                    Button("Забыли пароль?", action: resetPassword)
                        .disabled(!emailLooksValid || isWorking)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(messageIsError ? Color.red : Theme.herb)
                }
            }
        }
        .sheet(isPresented: $showsRules) {
            NavigationStack {
                CommunityRulesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showsRules = false }
                        }
                    }
            }
        }
        .onChange(of: mode) { _, _ in message = nil }
    }

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn:
            return emailLooksValid && !password.isEmpty
        case .signUp:
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return emailLooksValid && password.count >= 8 && (2...40).contains(trimmedName.count) && acceptsRules
        }
    }

    private func submit() {
        isWorking = true
        message = nil
        Task {
            do {
                switch mode {
                case .signIn:
                    try await community.signIn(email: email, password: password)
                case .signUp:
                    try await community.signUp(name: name, email: email, password: password)
                }
                password = ""
            } catch {
                messageIsError = true
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func resetPassword() {
        isWorking = true
        Task {
            do {
                try await community.requestPasswordReset(email: email)
                messageIsError = false
                message = "Если такой аккаунт есть, на почту придёт письмо со ссылкой для нового пароля."
            } catch {
                messageIsError = true
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Аккаунт: мои рецепты, скрытые авторы, выход и удаление.
struct CommunityAccountView: View {
    @Environment(CommunityStore.self) private var community

    @State private var myRecipes: [CommunityRecipe] = []
    @State private var loadError: String?
    @State private var editor: RecipeEditorRequest?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmsDelete = false
    @State private var isWorking = false
    @State private var toast: String?

    var body: some View {
        Group {
            if !community.isConfigured {
                CommunityNotConfiguredView()
            } else if let user = community.user {
                account(user)
            } else {
                CommunityAuthForm(reason: "Аккаунт нужен, чтобы публиковать рецепты, фото и отзывы. Смотреть и искать рецепты можно и без него.")
            }
        }
        .navigationTitle("Аккаунт")
        .task(id: "\(community.user?.id ?? "-")-\(community.revision)") {
            await loadMyRecipes()
        }
        .sheet(item: $editor) { request in
            RecipeEditorView(existing: request.recipe) { _ in
                toast = request.recipe == nil ? "Рецепт сохранён" : "Изменения сохранены"
            }
        }
        .toast($toast)
    }

    private func account(_ user: CommunityUser) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AuthorAvatar(name: user.name, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.display(.title3))
                        Text(user.email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Изменить имя") {
                    newName = user.name
                    renaming = true
                }
            }

            Section {
                Button {
                    editor = RecipeEditorRequest(recipe: nil)
                } label: {
                    Label("Новый рецепт", systemImage: "plus.circle.fill")
                }
                ForEach(myRecipes) { recipe in
                    NavigationLink(value: Route.communityRecipe(recipe.id)) {
                        MyRecipeRow(recipe: recipe)
                    }
                }
                if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Мои рецепты")
            } footer: {
                if myRecipes.isEmpty && loadError == nil {
                    Text("Поделитесь фирменным блюдом: с фото, ингредиентами и пошаговым рецептом.")
                }
            }

            if !community.blockedAuthors.isEmpty {
                Section {
                    ForEach(community.blockedAuthors.sorted { $0.value < $1.value }, id: \.key) { author in
                        HStack {
                            Text(author.value)
                            Spacer()
                            Button("Показать") { community.unblock(author.key) }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Скрытые авторы")
                } footer: {
                    Text("Рецепты и отзывы этих людей не показываются в вашей ленте.")
                }
            }

            Section {
                NavigationLink(value: Route.communityRules) {
                    Label("Правила сообщества", systemImage: "hand.raised")
                }
                if let email = CommunityConfig.supportEmail, let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) {
                        Label("Написать модератору", systemImage: "envelope")
                    }
                }
            }

            Section {
                Button("Выйти из аккаунта") { community.signOut() }
                Button("Удалить аккаунт", role: .destructive) { confirmsDelete = true }
            } footer: {
                Text("Удаление необратимо: исчезнут аккаунт, ваши рецепты, отзывы и фото. Дневник готовки на телефоне останется.")
            }
        }
        .disabled(isWorking)
        .overlay {
            if isWorking { ProgressView() }
        }
        .alert("Имя в сообществе", isPresented: $renaming) {
            TextField("Имя", text: $newName)
            Button("Сохранить") { rename() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Его видят под вашими рецептами и отзывами.")
        }
        .confirmationDialog("Удалить аккаунт навсегда?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить аккаунт и мои материалы", role: .destructive) { deleteAccount() }
        } message: {
            Text("Рецепты, отзывы и фото будут удалены с сервера. Отменить это нельзя.")
        }
    }

    private func loadMyRecipes() async {
        guard community.user != nil else {
            myRecipes = []
            return
        }
        do {
            myRecipes = try await community.myRecipes()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...40).contains(name.count) else {
            toast = "Имя — от 2 до 40 символов"
            return
        }
        isWorking = true
        Task {
            do {
                try await community.rename(name)
                toast = "Имя изменено"
            } catch {
                toast = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func deleteAccount() {
        isWorking = true
        Task {
            do {
                try await community.deleteAccount()
                toast = "Аккаунт удалён"
            } catch {
                toast = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Запрос на открытие редактора: новый рецепт или правка существующего.
struct RecipeEditorRequest: Identifiable {
    let recipe: CommunityRecipe?

    var id: String { recipe?.id ?? "new" }
}

private struct MyRecipeRow: View {
    let recipe: CommunityRecipe

    var body: some View {
        HStack(spacing: 12) {
            CommunityRecipeCover(recipe: recipe)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if recipe.isHidden {
                        Tag(title: "Скрыт модератором", systemImage: "eye.slash", tint: .red)
                    } else if !recipe.isPublished {
                        Tag(title: "Черновик", systemImage: "pencil", tint: .secondary)
                    } else {
                        RatingBadge(rating: recipe.rating)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

/// Кружок с первой буквой имени.
struct AuthorAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let colors: [Color] = [Theme.accent, Theme.herb, Theme.gold, Color(hex: "#3D5A80"), Color(hex: "#8E2347")]
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.45, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(colors[Int(DailyPick.stableHash(name) % UInt64(colors.count))], in: Circle())
            .accessibilityHidden(true)
    }
}

/// Правила сообщества: их принимают при регистрации.
struct CommunityRulesView: View {
    private let rules: [(String, String)] = [
        ("Делитесь своим", "Публикуйте свои рецепты и свои фотографии. Чужие тексты и фото — только с разрешения автора и с указанием источника."),
        ("Без грубости", "Мы не терпим оскорблений, угроз, травли, дискриминации, непристойных и жестоких материалов. Такие публикации удаляются, а их авторы блокируются."),
        ("Без рекламы и спама", "Не продавайте, не размещайте ссылки на магазины и не публикуйте одно и то же много раз."),
        ("Безопасность прежде всего", "Не советуйте опасного: сырую курицу, сомнительные грибы, «лечебные» рецепты вместо врача. Не публикуйте чужие персональные данные."),
        ("Пожаловаться и скрыть", "Увидели нарушение — нажмите «Пожаловаться». Модератор проверяет жалобы в течение суток, а материал с несколькими жалобами скрывается сразу. Любого автора можно скрыть: его рецепты и отзывы пропадут из вашей ленты."),
        ("Ваши права", "Права на рецепты и фото остаются у вас: вы разрешаете показывать их в приложении. Удалить аккаунт со всеми материалами можно в любой момент в разделе «Аккаунт».")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Deshielo — сообщество людей, которые любят готовить и делиться. Чтобы здесь было приятно, договоримся о простых правилах.")
                    .font(.system(.body, design: .serif))
                ForEach(Array(rules.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(item.offset + 1)")
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.14), in: Circle())
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.element.0)
                                .font(.headline)
                            Text(item.element.1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let email = CommunityConfig.supportEmail {
                    Text("Связаться с модератором: \(email)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Правила сообщества")
        .navigationBarTitleDisplayMode(.inline)
    }
}
