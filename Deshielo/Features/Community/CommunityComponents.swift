import PhotosUI
import SwiftUI
import UIKit

/// Фото с сервера сообщества. Файлы кешируются в URLCache — сервер отдаёт их с долгим сроком хранения.
struct CommunityImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        #if DEBUG
        if url.scheme == DemoPhoto.scheme {
            DishArtwork(recipe: DemoPhoto.recipe(for: url), showsYear: false)
        } else {
            remote
        }
        #else
        remote
        #endif
    }

    private var remote: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    Theme.surfaceSecondary
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            default:
                ZStack {
                    Theme.surfaceSecondary
                    ProgressView()
                }
            }
        }
    }
}

/// «4,7» — рейтинг с запятой, как принято по-русски.
enum RatingText {
    static func average(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ru_RU")))
    }

    static func summary(_ rating: RatingSummary) -> String {
        "\(average(rating.average)) · \(RussianPlural.phrase(rating.count, "оценка", "оценки", "оценок"))"
    }
}

/// Пять звёзд с частичным заполнением.
struct RatingStars: View {
    let value: Double
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: symbol(for: index))
            }
        }
        .font(.system(size: size))
        .foregroundStyle(Theme.gold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оценка \(RatingText.average(value)) из 5")
    }

    private func symbol(for index: Int) -> String {
        let position = Double(index)
        if value >= position - 0.25 { return "star.fill" }
        if value >= position - 0.75 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Компактная метка рейтинга: ★ 4,7 (18).
struct RatingBadge: View {
    let rating: RatingSummary

    var body: some View {
        if rating.count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.gold)
                Text(RatingText.average(rating.average))
                    .fontWeight(.semibold)
                Text("(\(rating.count))")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Рейтинг \(RatingText.average(rating.average)), \(RussianPlural.phrase(rating.count, "оценка", "оценки", "оценок"))")
        } else {
            Text("Нет оценок")
                .foregroundStyle(.secondary)
        }
    }
}

/// Выбор оценки звёздами.
struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 14) {
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
                .accessibilityAddTraits(value == rating ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: rating)
    }
}

/// Кнопка «Добавить фото»: камера или галерея.
struct PhotoSourceButton<Label: View>: View {
    var maxCount = 1
    let onPick: ([UIImage]) -> Void
    @ViewBuilder let label: () -> Label

    @State private var choosesSource = false
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var items: [PhotosPickerItem] = []

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button {
            if cameraAvailable {
                choosesSource = true
            } else {
                showsLibrary = true
            }
        } label: {
            label()
        }
        .confirmationDialog("Добавить фото", isPresented: $choosesSource) {
            Button("Сделать фото") { showsCamera = true }
            Button("Выбрать из галереи") { showsLibrary = true }
        }
        .photosPicker(isPresented: $showsLibrary, selection: $items, maxSelectionCount: max(1, maxCount),
                      matching: .images, preferredItemEncoding: .compatible)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(onPick: { onPick([$0]) }, onClose: { showsCamera = false })
                .ignoresSafeArea()
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                items = []
                if !images.isEmpty { onPick(images) }
            }
        }
    }
}

/// Съёмка камерой через системный экран.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}

/// Фото на весь экран.
struct PhotoViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            CommunityImage(url: url, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Закрыть")
        }
    }
}

/// Показывает содержимое только в аккаунте; иначе — форму входа.
struct CommunityGate<Content: View>: View {
    let reason: String
    @ViewBuilder let content: () -> Content

    @Environment(CommunityStore.self) private var community

    var body: some View {
        if !community.isConfigured {
            CommunityNotConfiguredView()
        } else if community.user == nil {
            CommunityAuthForm(reason: reason)
        } else {
            content()
        }
    }
}

/// Сервер сообщества не подключён в этой сборке.
struct CommunityNotConfiguredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Сообщество не подключено", systemImage: "person.2.slash")
        } description: {
            Text("Чтобы публиковать рецепты, фото и отзывы, нужен сервер сообщества. Как его запустить — в docs/COMMUNITY.md.")
        }
    }
}

/// Жалоба на рецепт или отзыв.
struct ReportSheet: View {
    let target: ReportTarget
    let onSent: () -> Void

    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .offensive
    @State private var comment = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            CommunityGate(reason: "Войдите, чтобы отправить жалобу.") {
                Form {
                    Section("Что не так?") {
                        Picker("Причина", selection: $reason) {
                            ForEach(ReportReason.allCases) { reason in
                                Text(reason.title).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section {
                        TextField("Подробности (необязательно)", text: $comment, axis: .vertical)
                            .lineLimit(2...5)
                    } footer: {
                        Text("Модератор проверит жалобу в течение суток. Если пожалуются несколько человек, материал скроется сразу.")
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                if community.user != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Отправить") { send() }
                            .disabled(isSending)
                    }
                }
            }
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            do {
                try await community.report(target, reason: reason, comment: comment)
                onSent()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}

extension Date {
    /// «3 часа назад», «вчера».
    var relativeText: String {
        formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "ru_RU")))
    }
}
