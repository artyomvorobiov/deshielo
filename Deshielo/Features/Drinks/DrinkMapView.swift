import MapKit
import SwiftUI

/// Карта: винодельческие регионы и места, откуда родом чаи.
struct DrinkMapView: View {
    private enum Layer: String, CaseIterable, Identifiable {
        case all, wine, tea

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "Всё"
            case .wine: "Вино"
            case .tea: "Чай"
            }
        }
    }

    enum Place: Hashable, Identifiable {
        case region(WineRegion)
        case tea(Tea)

        var id: String {
            switch self {
            case .region(let region): "region-\(region.id)"
            case .tea(let tea): "tea-\(tea.id)"
            }
        }

        var name: String {
            switch self {
            case .region(let region): region.name
            case .tea(let tea): tea.name
            }
        }

        var coordinate: CLLocationCoordinate2D {
            switch self {
            case .region(let region): CLLocationCoordinate2D(latitude: region.lat, longitude: region.lon)
            case .tea(let tea): CLLocationCoordinate2D(latitude: tea.lat, longitude: tea.lon)
            }
        }

        var symbol: String {
            switch self {
            case .region: "wineglass"
            case .tea: "leaf"
            }
        }

        var color: Color {
            switch self {
            case .region: Color(hex: "#7B1E2E")
            case .tea: Theme.herb
            }
        }

        var route: Route {
            switch self {
            case .region(let region): .wineRegion(region.id)
            case .tea(let tea): .tea(tea.id)
            }
        }
    }

    @Environment(\.drinks) private var drinks
    @Environment(\.catalog) private var catalog

    @State private var layer: Layer = DrinksConfig.showsWine ? .all : .tea
    @State private var selected: Place?
    @State private var position: MapCameraPosition = .automatic

    private var places: [Place] {
        var list: [Place] = []
        if DrinksConfig.showsWine && layer != .tea {
            list += drinks.wine.regions.map(Place.region)
        }
        if layer != .wine {
            list += drinks.tea.teas.map(Place.tea)
        }
        return list
    }

    var body: some View {
        Map(position: $position) {
            ForEach(places) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Button {
                        withAnimation(.snappy) { selected = place }
                    } label: {
                        Image(systemName: place.symbol)
                            .font(.system(size: selected == place ? 18 : 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: selected == place ? 38 : 28, height: selected == place ? 38 : 28)
                            .background(place.color, in: Circle())
                            .overlay { Circle().stroke(.white, lineWidth: 2) }
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .top) {
            if DrinksConfig.showsWine {
                Picker("Что показать", selection: $layer) {
                    ForEach(Layer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                PlaceCard(place: selected) {
                    withAnimation(.snappy) { self.selected = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text(DrinksConfig.showsWine ? "Бокал — винодельческий регион, лист — родина чая"
                                            : "Нажмите на лист, чтобы узнать о чае")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: layer) { _, _ in
            selected = nil
            withAnimation { position = .automatic }
        }
        .navigationTitle(DrinksConfig.showsWine ? "Карта вин и чая" : "Карта чая")
        .navigationBarTitleDisplayMode(.inline)
    }

    struct PlaceCard: View {
        let place: Place
        let onClose: () -> Void

        @Environment(\.catalog) private var catalog

        var body: some View {
            HStack(spacing: 14) {
                artwork
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.display(.headline))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    NavigationLink(value: place.route) {
                        Text("Подробнее")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }

        @ViewBuilder
        private var artwork: some View {
            switch place {
            case .region(let region): FlagBadge(code: region.country)
            case .tea(let tea): DrinkArtwork(tea: tea)
            }
        }

        private var subtitle: String {
            switch place {
            case .region(let region):
                "\(CountryName.flag(region.country)) \(CountryName.name(region.country, catalog: catalog)) · \(region.summary)"
            case .tea(let tea):
                tea.origin
            }
        }
    }
}
