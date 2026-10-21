import SwiftUI
import UIKit

/// Обложка блюда. Если в Assets есть картинка с именем из поля `image` — показываем фото,
/// иначе рисуем генеративную иллюстрацию: вид сверху на тарелку в цветах блюда.
/// Для исторических рецептов — «архивная» версия на пергаменте с годом.
struct DishArtwork: View {
    let recipe: Recipe
    var showsYear: Bool = true

    var body: some View {
        if let name = recipe.image, let photo = UIImage(named: name) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            GeometryReader { proxy in
                ArtworkCanvas(spec: ArtworkSpec(recipe: recipe), size: proxy.size, showsYear: showsYear)
            }
        }
    }
}

/// Параметры иллюстрации, вычисленные из рецепта детерминированно (одинаково при каждом запуске).
struct ArtworkSpec {
    struct Blob {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let angle: Double
    }

    struct Dot {
        let x: Double
        let y: Double
        let radius: Double
        let usesGarnish: Bool
    }

    let main: Color
    let mainLight: Color
    let secondary: Color
    let garnish: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let plate: Color
    let rim: Color
    let ink: Color
    let isArchive: Bool
    let yearText: String?
    let blobs: [Blob]
    let swoosh: Blob
    let dots: [Dot]

    init(recipe: Recipe) {
        let colors = recipe.palette.map(UIColor.init(hex:))
        let mainUI = colors.first ?? UIColor(rgb: 0xC98B3C)
        let secondaryUI = colors.count > 1 ? colors[1] : UIColor(rgb: 0xE8D9C4)
        let garnishUI = colors.count > 2 ? colors[2] : UIColor(rgb: 0x6E8B3D)

        main = Color(uiColor: mainUI)
        mainLight = Color(uiColor: mainUI.mixed(with: .white, amount: 0.28))
        secondary = Color(uiColor: secondaryUI)
        garnish = Color(uiColor: garnishUI)

        let archive = recipe.isHistoric
        isArchive = archive
        yearText = recipe.year.map(YearText.short)
        if archive {
            backgroundTop = Color(uiColor: UIColor(rgb: 0xF3E9D6))
            backgroundBottom = Color(uiColor: UIColor(rgb: 0xE2D0AC))
            ink = Color(uiColor: UIColor(rgb: 0x5A4632))
        } else {
            backgroundTop = Color(uiColor: mainUI.mixed(with: .black, amount: 0.55))
            backgroundBottom = Color(uiColor: secondaryUI.mixed(with: .black, amount: 0.72))
            ink = Color(uiColor: UIColor(rgb: 0xF2EAE0))
        }

        // Светлое блюдо (пюре, крем, меренга) кладём на тёмную тарелку, чтобы его было видно.
        if mainUI.luminance > 0.78 {
            plate = Color(uiColor: UIColor(rgb: 0x2A2522))
            rim = Color(uiColor: UIColor(rgb: 0x4A423C))
        } else {
            plate = Color(uiColor: UIColor(rgb: 0xF8F2E9))
            rim = Color(uiColor: UIColor(rgb: 0xE6DBCB))
        }

        var random = SeededGenerator(string: recipe.id)
        blobs = (0..<3).map { index in
            Blob(x: random.range(-0.08, 0.08),
                 y: random.range(-0.08, 0.06),
                 width: random.range(0.36, 0.5) - Double(index) * 0.04,
                 height: random.range(0.26, 0.36) - Double(index) * 0.03,
                 angle: random.range(-40, 40))
        }
        swoosh = Blob(x: random.range(-0.06, 0.06),
                      y: random.range(0.08, 0.16),
                      width: random.range(0.62, 0.78),
                      height: random.range(0.1, 0.15),
                      angle: random.range(-35, 35))
        dots = (0..<7).map { _ in
            let angle = random.range(0, 2 * Double.pi)
            let distance = random.range(0.2, 0.36)
            return Dot(x: cos(angle) * distance,
                       y: sin(angle) * distance,
                       radius: random.range(0.018, 0.04),
                       usesGarnish: random.unit() > 0.35)
        }
    }
}

struct ArtworkCanvas: View {
    let spec: ArtworkSpec
    let size: CGSize
    let showsYear: Bool

    private var side: CGFloat { min(size.width, size.height) }
    private var showsCaption: Bool { spec.isArchive && showsYear && spec.yearText != nil && side > 90 }
    private var plateDiameter: CGFloat { side * (spec.isArchive ? 0.66 : 0.8) }
    private var wellDiameter: CGFloat { plateDiameter * 0.74 }
    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 - (showsCaption ? side * 0.06 : 0))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [spec.backgroundTop, spec.backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(spec.isArchive ? 0.35 : 0.12), .clear],
                           center: .topLeading, startRadius: 0, endRadius: side * 0.9)
            if spec.isArchive {
                Rectangle()
                    .strokeBorder(spec.ink.opacity(0.35), lineWidth: max(0.5, side * 0.004))
                    .padding(side * 0.045)
            }
            Circle()
                .fill(Color.black.opacity(spec.isArchive ? 0.18 : 0.32))
                .frame(width: plateDiameter, height: plateDiameter)
                .blur(radius: side * 0.035)
                .position(x: center.x, y: center.y + side * 0.025)
            Circle()
                .fill(spec.plate)
                .frame(width: plateDiameter, height: plateDiameter)
                .position(center)
            Circle()
                .stroke(spec.rim, lineWidth: max(1, side * 0.007))
                .frame(width: wellDiameter * 1.05, height: wellDiameter * 1.05)
                .position(center)
            food
                .frame(width: wellDiameter, height: wellDiameter)
                .clipShape(Circle())
                .position(center)
            if showsCaption, let year = spec.yearText {
                Text(year)
                    .font(.system(size: side * 0.085, weight: .semibold, design: .serif))
                    .foregroundStyle(spec.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: size.width * 0.8)
                    .position(x: size.width / 2, y: size.height - side * 0.12)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var food: some View {
        let d = wellDiameter
        return ZStack {
            Capsule()
                .fill(spec.secondary)
                .frame(width: d * spec.swoosh.width, height: d * spec.swoosh.height)
                .rotationEffect(.degrees(spec.swoosh.angle))
                .position(x: d * (0.5 + spec.swoosh.x), y: d * (0.5 + spec.swoosh.y))
            ForEach(Array(spec.blobs.enumerated()), id: \.offset) { item in
                Ellipse()
                    .fill(RadialGradient(colors: [spec.mainLight, spec.main],
                                         center: .topLeading, startRadius: 0, endRadius: d * 0.45))
                    .frame(width: d * item.element.width, height: d * item.element.height)
                    .rotationEffect(.degrees(item.element.angle))
                    .position(x: d * (0.5 + item.element.x), y: d * (0.5 + item.element.y))
            }
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: d * 0.14, height: d * 0.06)
                .rotationEffect(.degrees(-20))
                .position(x: d * (0.42 + spec.blobs[0].x), y: d * (0.42 + spec.blobs[0].y))
            ForEach(Array(spec.dots.enumerated()), id: \.offset) { item in
                Circle()
                    .fill(item.element.usesGarnish ? spec.garnish : spec.secondary)
                    .frame(width: d * item.element.radius * 2, height: d * item.element.radius * 2)
                    .position(x: d * (0.5 + item.element.x), y: d * (0.5 + item.element.y))
            }
        }
        .frame(width: d, height: d)
    }
}

extension UIColor {
    /// Смешивание цветов: amount = 0 — исходный цвет, 1 — второй цвет.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}

/// Монограмма шефа или коллекции: инициалы на градиенте.
struct MonogramView: View {
    let text: String
    let palette: [String]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: palette.prefix(2).map(Color.init(hex:)),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(text)
                    .font(.system(size: side * 0.38, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .minimumScaleFactor(0.5)
            }
        }
    }
}
