import SwiftUI
import UIKit

/// Фото на весь экран — элемент для fullScreenCover.
struct PhotoViewerItem: Identifiable {
    let url: URL

    var id: URL { url }
}

/// Запрос на открытие редактора отзыва.
struct ReviewComposerRequest: Identifiable {
    let existing: CommunityReview?

    var id: String { existing?.id ?? "new" }
}

/// «Как получилось у других»: оценки, фото результатов и отзывы.
/// Общий для рецептов из каталога и рецептов сообщества.
struct ReviewsSection: View {
    let target: ReviewTarget
    let recipeTitle: String
    var summary: RatingSummary?
    /// Свой рецепт оценить нельзя.
    var allowsReview = true
    var onMessage: (String) -> Void = { _ in }

    @Environment(CommunityStore.self) private var community
    @State private var reviews: [CommunityReview] = []
    @State private var myReview: CommunityReview?
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var composer: ReviewComposerRequest?
    @State private var reporting: ReportTarget?
    @State private var viewer: PhotoViewerItem?
    @State private var deleting: CommunityReview?

    var body: some View {
        if community.isConfigured {
            content
                .task(id: "\(community.revision)-\(community.user?.id ?? "-")") { await load() }
                .sheet(item: $composer) { request in
                    ReviewComposerSheet(target: target, recipeTitle: recipeTitle, existing: request.existing) { _ in
                        onMessage(request.existing == nil ? "Спасибо! Отзыв опубликован" : "Отзыв обновлён")
                    }
                }
                .sheet(item: $reporting) { target in
                    ReportSheet(target: target) { onMessage("Жалоба отправлена. Спасибо!") }
                }
                .fullScreenCover(item: $viewer) { item in
                    PhotoViewer(url: item.url)
                }
                .confirmationDialog("Удалить отзыв?", isPresented: Binding(get: { deleting != nil },
                                                                          set: { if !$0 { deleting = nil } }),
                                    titleVisibility: .visible, presenting: deleting) { review in
                    Button("Удалить", role: .destructive) { delete(review) }
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Как получилось у других", subtitle: subtitle)
            if !photoReviews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photoReviews) { review in
                            if let photo = review.photo {
                                Button {
                                    viewer = PhotoViewerItem(url: photo.url)
                                } label: {
                                    Color.clear
                                        .frame(width: 104, height: 104)
                                        .overlay { CommunityImage(url: photo.thumbnailURL) }
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Фото от \(review.author.name)")
                            }
                        }
                    }
                }
            }
            ForEach(reviews) { review in
                ReviewRow(review: review,
                          isMine: community.isMine(review.author),
                          onPhoto: { viewer = PhotoViewerItem(url: $0) },
                          onEdit: { composer = ReviewComposerRequest(existing: review) },
                          onDelete: { deleting = review },
                          onReport: { reporting = .review(review.id) },
                          onBlock: {
                              community.block(review.author)
                              onMessage("Отзывы \(review.author.name) скрыты")
                          })
            }
            if hasMore {
                Button("Показать ещё") {
                    Task { await loadMore() }
                }
                .font(.subheadline.weight(.medium))
            }
            if let loadError, reviews.isEmpty {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if allowsReview {
                Button {
                    composer = ReviewComposerRequest(existing: myReview)
                } label: {
                    Label(myReview == nil ? "Оценить и показать своё фото" : "Изменить мой отзыв",
                          systemImage: myReview == nil ? "camera" : "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photoReviews: [CommunityReview] { reviews.filter { $0.photo != nil } }

    private var rating: RatingSummary? {
        if let summary, summary.count > 0 { return summary }
        if case .catalog(let id) = target { return community.rating(forCatalog: id) }
        return nil
    }

    private var subtitle: String {
        if let rating {
            return "★ \(RatingText.summary(rating))"
        }
        if isLoading && reviews.isEmpty { return "Загружаем отзывы…" }
        return reviews.isEmpty ? "Пока нет отзывов — приготовьте и расскажите первым" : RussianPlural.phrase(reviews.count, "отзыв", "отзыва", "отзывов")
    }

    private func load() async {
        isLoading = true
        do {
            let result = try await community.reviews(for: target, page: 1)
            reviews = result.items
            hasMore = result.hasMore
            page = 1
            loadError = nil
            myReview = reviews.first { community.isMine($0.author) }
            if myReview == nil, community.user != nil {
                myReview = try await community.myReview(for: target)
            }
        } catch is CancellationError {
            // Экран закрыли.
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        if let next = try? await community.reviews(for: target, page: page + 1) {
            let known = Set(reviews.map(\.id))
            reviews += next.items.filter { !known.contains($0.id) }
            hasMore = next.hasMore
            page += 1
        } else {
            hasMore = false
        }
        isLoading = false
    }

    private func delete(_ review: CommunityReview) {
        Task {
            do {
                try await community.deleteReview(review)
                onMessage("Отзыв удалён")
            } catch {
                onMessage(error.localizedDescription)
            }
        }
    }
}

/// Один отзыв: автор, звёзды, текст и фото.
struct ReviewRow: View {
    let review: CommunityReview
    let isMine: Bool
    let onPhoto: (URL) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AuthorAvatar(name: review.author.name, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMine ? "\(review.author.name) (вы)" : review.author.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        RatingStars(value: Double(review.rating), size: 11)
                        Text(review.created.relativeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    if isMine {
                        Button("Изменить", systemImage: "pencil", action: onEdit)
                        Button("Удалить", systemImage: "trash", role: .destructive, action: onDelete)
                    } else {
                        Button("Пожаловаться", systemImage: "exclamationmark.bubble", action: onReport)
                        Button("Скрыть автора", systemImage: "eye.slash", action: onBlock)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Действия с отзывом")
            }
            if !review.comment.isEmpty {
                Text(review.comment)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let photo = review.photo {
                Button {
                    onPhoto(photo.url)
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .overlay { CommunityImage(url: photo.thumbnailURL) }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Фото результата")
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Отзыв: звёзды, фото результата и пара слов.
struct ReviewComposerSheet: View {
    let target: ReviewTarget
    let recipeTitle: String
    let existing: CommunityReview?
    var initialRating = 0
    var initialComment = ""
    var initialPhoto: UIImage?
    let onSaved: (CommunityReview) -> Void

    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var comment = ""
    @State private var photo: UIImage?
    @State private var removesExistingPhoto = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            CommunityGate(reason: "Войдите, чтобы оценить рецепт и поделиться фото результата.") {
                form
            }
            .navigationTitle(recipeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                if community.user != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Опубликовать", action: save)
                                .disabled(rating == 0)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear(perform: prefill)
    }

    private var form: some View {
        Form {
            Section("Ваша оценка") {
                StarRatingPicker(rating: $rating)
                    .padding(.vertical, 6)
            }
            Section {
                photoField
            } header: {
                Text("Фото результата")
            } footer: {
                Text("Покажите, что получилось, — так другим проще решиться.")
            }
            Section("Отзыв") {
                TextField("Как получилось и что бы вы изменили", text: $comment, axis: .vertical)
                    .lineLimit(3...8)
            }
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var photoField: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            Button("Убрать фото", role: .destructive) { self.photo = nil }
        } else if let existingPhoto = existing?.photo, !removesExistingPhoto {
            Color.clear
                .frame(height: 220)
                .overlay { CommunityImage(url: existingPhoto.thumbnailURL) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            PhotoSourceButton(onPick: { photo = $0.first }) {
                Label("Заменить фото", systemImage: "arrow.triangle.2.circlepath.camera")
            }
            Button("Убрать фото", role: .destructive) { removesExistingPhoto = true }
        } else {
            PhotoSourceButton(onPick: { photo = $0.first }) {
                Label("Добавить фото", systemImage: "camera")
            }
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        rating = existing?.rating ?? initialRating
        comment = existing?.comment ?? initialComment
        if photo == nil {
            photo = initialPhoto
        }
    }

    private func save() {
        isSaving = true
        error = nil
        let draft = ReviewDraft(rating: rating, comment: comment,
                                newPhoto: photo.flatMap { ImageCompressor.jpegData(from: $0) },
                                removesPhoto: removesExistingPhoto)
        Task {
            do {
                let review = try await community.saveReview(draft, for: target, existingID: existing?.id)
                onSaved(review)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}
