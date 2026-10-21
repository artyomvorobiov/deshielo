import SwiftUI

/// Конвертер: граммы в ложках и стаканах, старинные меры, температура духовки.
struct ConverterView: View {
    @Environment(\.catalog) private var catalog

    @State private var productID = "flour"
    @State private var grams = "100"
    @State private var historicID = "funt"
    @State private var historicAmount = "1"

    var body: some View {
        let measures = catalog.measures
        let product = measures.products.first { $0.id == productID } ?? measures.products.first
        let historic = measures.historic.first { $0.id == historicID } ?? measures.historic.first
        Form {
            Section {
                Picker("Продукт", selection: $productID) {
                    ForEach(measures.products) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                if let product {
                    ForEach(measures.volumes) { volume in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(volume.name)
                                Text(volume.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("≈ \(Self.format(volume.ml * product.density)) г")
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Сколько граммов в ложке и стакане")
            } footer: {
                Text("Значения приблизительные: многое зависит от того, как насыпать продукт.")
            }

            Section("Граммы → ложки и стаканы") {
                HStack {
                    TextField("Граммы", text: $grams)
                        .keyboardType(.decimalPad)
                    Text("г")
                        .foregroundStyle(.secondary)
                }
                if let product, let value = Self.parse(grams), value > 0 {
                    ForEach(measures.volumes) { volume in
                        HStack {
                            Text(volume.name)
                            Spacer()
                            Text(Self.format(value / (volume.ml * product.density)))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Picker("Мера", selection: $historicID) {
                    ForEach(measures.historic) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                HStack {
                    TextField("Количество", text: $historicAmount)
                        .keyboardType(.decimalPad)
                    Spacer()
                    if let historic, let amount = Self.parse(historicAmount), amount > 0 {
                        Text("≈ \(AmountFormatter.metric(amount * historic.value, small: historic.isMass ? "г" : "мл", large: historic.isMass ? "кг" : "л"))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }
                ForEach(measures.historic) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.origin)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AmountFormatter.metric(item.value, small: item.isMass ? "г" : "мл", large: item.isMass ? "кг" : "л"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Старинные меры")
            } footer: {
                Text("Пригодятся для рецептов Молоховец, Катона и старинных английских книг.")
            }

            Section("Температура духовки") {
                ForEach(measures.ovenMarks, id: \.gas) { mark in
                    HStack {
                        Text("Газ \(mark.gas)")
                        Spacer()
                        Text("\(mark.celsius) °C · \(mark.fahrenheit) °F")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Конвертер мер")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    static func format(_ value: Double) -> String {
        if value >= 10 {
            return String(Int(value.rounded()))
        }
        return AmountFormatter.number((value * 10).rounded() / 10, fractions: false)
    }
}

/// Словарь шефа: кулинарные техники и термины.
struct GlossaryView: View {
    @Environment(\.catalog) private var catalog

    @State private var query = ""
    @State private var selected: GlossaryTerm?

    var body: some View {
        let needle = query.searchNormalized
        let terms = catalog.glossary.filter { term in
            needle.isEmpty
                || term.term.searchNormalized.contains(needle)
                || term.definition.searchNormalized.contains(needle)
        }
        List(terms) { term in
            Button {
                selected = term
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(term.term)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(term.definition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $query, prompt: "Термин или техника")
        .navigationTitle("Словарь шефа")
        .sheet(item: $selected) { term in
            TermSheet(term: term)
        }
    }
}
