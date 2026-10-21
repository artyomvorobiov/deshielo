import SwiftUI
import UIKit

/// Заказ продуктов: выбор сервиса и поиск каждого продукта в его приложении или на сайте.
/// Публичных API для добавления в корзину у сервисов нет, поэтому открываем поиск,
/// а название продукта заранее копируем — если поиск не сработает, его можно просто вставить.
struct DeliverySheet: View {
    @Environment(\.catalog) private var catalog
    @Environment(ShoppingStore.self) private var shopping
    @Environment(ProfileStore.self) private var profile
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var toast: String?

    private var services: [DeliveryService] { catalog.delivery.filter { $0.kind == .groceries } }

    private var selected: DeliveryService? {
        services.first { $0.id == profile.preferredDeliveryID } ?? services.first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(services) { service in
                                Chip(title: service.name, isSelected: service.id == selected?.id) {
                                    profile.preferredDeliveryID = service.id
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Сервис")
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                if let service = selected {
                    Section {
                        ForEach(shopping.items.filter { !$0.isChecked }) { item in
                            HStack(spacing: 12) {
                                Button {
                                    shopping.toggle(item)
                                } label: {
                                    Image(systemName: "circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Отметить купленным")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    if !item.amountText.isEmpty {
                                        Text(item.amountText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    search(item.name, in: service)
                                } label: {
                                    Label("Найти", systemImage: "magnifyingglass")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                            }
                        }
                    } header: {
                        Text("Продукты")
                    } footer: {
                        Text("«Найти» копирует название и открывает поиск в \(service.name). Купленное отмечайте кружком слева.")
                    }

                    Section {
                        Button {
                            UIPasteboard.general.string = shopping.shareText()
                            openURL(service.homeURL)
                        } label: {
                            Label("Скопировать весь список и открыть \(service.name)", systemImage: "doc.on.doc")
                        }
                    } footer: {
                        Text("Deshielo не связан с сервисами доставки. Ассортимент и цены — на стороне сервиса.")
                    }
                }
            }
            .navigationTitle("Заказать продукты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .toast($toast)
        }
    }

    private func search(_ name: String, in service: DeliveryService) {
        UIPasteboard.general.string = name
        toast = "«\(name)» скопировано"
        openURL(service.url(for: name))
    }
}
