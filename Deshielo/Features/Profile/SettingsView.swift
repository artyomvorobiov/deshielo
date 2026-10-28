import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile
    @Environment(TastingStore.self) private var tastings
    @Environment(\.openURL) private var openURL

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var confirmsReset = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var profile = profile
        Form {
            Section("Готовка") {
                Toggle("Читать шаги вслух", isOn: $profile.speakSteps)
                Toggle("Добавлять соль, перец и масло в покупки", isOn: $profile.includeStaples)
            }

            Section("Доставка продуктов") {
                Picker("Сервис по умолчанию", selection: deliveryBinding) {
                    ForEach(catalog.delivery.filter { $0.kind == .groceries }) { service in
                        Text(service.name).tag(service.id)
                    }
                }
            }

            Section {
                HStack {
                    Text("Уведомления")
                    Spacer()
                    Text(notificationText)
                        .foregroundStyle(.secondary)
                }
                if notificationStatus == .denied {
                    Button("Открыть настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } header: {
                Text("Таймеры")
            } footer: {
                Text("Когда таймер сработает, придёт уведомление, а обратный отсчёт виден в Dynamic Island и на экране блокировки.")
            }

            Section {
                Label(AppGroup.isAvailable ? "Общие данные с виджетами подключены" : "Виджеты не видят данные приложения",
                      systemImage: AppGroup.isAvailable ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(AppGroup.isAvailable ? Theme.herb : Color.orange)
            } header: {
                Text("Виджеты")
            } footer: {
                Text(AppGroup.isAvailable
                     ? "Добавьте виджеты «Рецепт дня», «Покупки» и «Паспорт»: долгое нажатие на экран «Домой» → «Изменить» → «Добавить виджет»."
                     : "Проверьте App Group в настройках подписи проекта (см. README). Приложение работает и без этого.")
            }

            Section("О приложении") {
                LabeledContent("Версия", value: version)
                LabeledContent("Рецептов", value: "\(catalog.recipes.count)")
                LabeledContent("Кухонь мира", value: "\(catalog.countriesWithRecipes.count)")
                Text("Рецепты шефов — домашние адаптации по мотивам их блюд, написанные редакцией. Исторические рецепты адаптированы под современные продукты; оригинальные тексты приводятся из источников, перешедших в общественное достояние. Калорийность приблизительная.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Deshielo не связан с упомянутыми шефами, ресторанами и сервисами доставки.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Сбросить мои данные", role: .destructive) {
                    confirmsReset = true
                }
            } footer: {
                Text("Удалит избранное, дневник готовки, дегустации, заметки, меню и отметки «Из холодильника». Список покупок останется.")
            }
        }
        .navigationTitle("Настройки")
        .task {
            notificationStatus = await NotificationService.authorizationStatus()
        }
        .confirmationDialog("Сбросить все личные данные?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) {
                profile.resetAll()
                tastings.resetAll()
            }
        }
    }

    private var deliveryBinding: Binding<String> {
        Binding(
            get: { profile.preferredDeliveryID ?? catalog.delivery.first?.id ?? "" },
            set: { profile.preferredDeliveryID = $0 }
        )
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized?, .provisional?, .ephemeral?: "Включены"
        case .denied?: "Выключены"
        case .notDetermined?: "Спросим при первом таймере"
        default: "—"
        }
    }
}
