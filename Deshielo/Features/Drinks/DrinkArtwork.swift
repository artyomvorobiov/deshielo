import SwiftUI
import UIKit

/// Иллюстрация напитка в цветах из палитры, как обложки блюд: бокал вина сбоку или чашка чая сверху.
struct DrinkArtwork: View {
    enum Vessel: Hashable {
        /// Бокал-тюльпан для тихих вин.
        case glass
        /// Высокий узкий флюте для игристого.
        case flute
        /// Маленький бокал для десертных и креплёных вин.
        case dessertGlass
        /// Чашка чая на блюдце, вид сверху.
        case cup
    }

    let palette: [String]
    let vessel: Vessel
    /// От него зависят случайные детали — пузырьки и чаинка. Одинаковы при каждом запуске.
    let seed: String

    var body: some View {
        Canvas { context, size in
            let colors = palette.map(UIColor.init(hex:))
            let main = colors.first ?? UIColor(rgb: 0x7B1E2E)
            let second = colors.count > 1 ? colors[1] : main.mixed(with: .white, amount: 0.4)
            let light = colors.count > 2 ? colors[2] : UIColor(rgb: 0xF6F2EC)
            if vessel == .cup {
                DrinkDrawing.cup(in: &context, size: size, liquid: main, accent: second, light: light, seed: seed)
            } else {
                DrinkDrawing.glass(in: &context, size: size, vessel: vessel, liquid: main, accent: second, seed: seed)
            }
        }
        .accessibilityHidden(true)
    }
}

extension DrinkArtwork {
    init(style: WineStyle) {
        self.init(palette: style.palette,
                  vessel: style.isSparkling ? .flute : style.isDessert ? .dessertGlass : .glass,
                  seed: style.id)
    }

    init(grape: Grape) {
        self.init(palette: grape.palette, vessel: .glass, seed: grape.id)
    }

    init(tea: Tea) {
        self.init(palette: tea.palette, vessel: .cup, seed: tea.id)
    }

    init(teaType: TeaType) {
        self.init(palette: teaType.palette, vessel: .cup, seed: teaType.id)
    }
}

/// Рисование бокала и чашки. Координаты задаются в долях квадрата, вписанного в иллюстрацию.
private enum DrinkDrawing {
    struct Frame {
        let origin: CGPoint
        let side: CGFloat

        init(size: CGSize) {
            side = min(size.width, size.height)
            origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        }

        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + u * side, y: origin.y + v * side)
        }

        func rect(_ u: CGFloat, _ v: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + u * side, y: origin.y + v * side, width: width * side, height: height * side)
        }
    }

    /// Форма чаши бокала: край, самая широкая часть, дно и уровень вина.
    struct GlassShape {
        let rimLeft: CGFloat
        let rimY: CGFloat
        let bulge: CGFloat
        let bulgeY: CGFloat
        let bottomY: CGFloat
        let level: CGFloat
        let footWidth: CGFloat

        init(_ vessel: DrinkArtwork.Vessel) {
            switch vessel {
            case .flute:
                rimLeft = 0.42; rimY = 0.1; bulge = 0.385; bulgeY = 0.36; bottomY = 0.62; level = 0.2; footWidth = 0.22
            case .dessertGlass:
                rimLeft = 0.385; rimY = 0.27; bulge = 0.335; bulgeY = 0.42; bottomY = 0.6; level = 0.38; footWidth = 0.22
            default:
                rimLeft = 0.335; rimY = 0.13; bulge = 0.255; bulgeY = 0.33; bottomY = 0.6; level = 0.36; footWidth = 0.28
            }
        }
    }

    static func background(in context: inout GraphicsContext, size: CGSize, top: UIColor, bottom: UIColor) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(uiColor: top), Color(uiColor: bottom)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        let side = min(size.width, size.height)
        context.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.16), .clear]),
            center: CGPoint(x: size.width * 0.2, y: size.height * 0.1), startRadius: 0, endRadius: side * 0.9))
    }

    static func glass(in context: inout GraphicsContext, size: CGSize, vessel: DrinkArtwork.Vessel,
                      liquid: UIColor, accent: UIColor, seed: String) {
        background(in: &context, size: size,
                   top: liquid.mixed(with: .black, amount: 0.62), bottom: accent.mixed(with: .black, amount: 0.78))
        let frame = Frame(size: size)
        let shape = GlassShape(vessel)
        let rimRight = 1 - shape.rimLeft
        let bulgeRight = 1 - shape.bulge

        var bowl = Path()
        bowl.move(to: frame.point(shape.rimLeft, shape.rimY))
        bowl.addCurve(to: frame.point(0.5, shape.bottomY),
                      control1: frame.point(shape.bulge - 0.03, shape.bulgeY),
                      control2: frame.point(shape.bulge + 0.05, shape.bottomY))
        bowl.addCurve(to: frame.point(rimRight, shape.rimY),
                      control1: frame.point(bulgeRight - 0.05, shape.bottomY),
                      control2: frame.point(bulgeRight + 0.03, shape.bulgeY))
        bowl.closeSubpath()

        // Тень под бокалом.
        let shadow = Path(ellipseIn: frame.rect(0.5 - shape.footWidth * 0.62, 0.86, shape.footWidth * 1.24, 0.05))
        context.fill(shadow, with: .color(.black.opacity(0.28)))

        // Вино: чаша, обрезанная по уровню, светлее у поверхности.
        var wine = context
        wine.clip(to: Path(frame.rect(0, shape.level, 1, 1)))
        wine.fill(bowl, with: .linearGradient(
            Gradient(colors: [Color(uiColor: liquid.mixed(with: .white, amount: 0.22)),
                              Color(uiColor: liquid.mixed(with: .black, amount: 0.25))]),
            startPoint: frame.point(0.5, shape.level), endPoint: frame.point(0.5, shape.bottomY)))
        // Поверхность вина.
        let surfaceWidth = (1 - 2 * shape.bulge) * 0.92
        let surface = Path(ellipseIn: frame.rect(0.5 - surfaceWidth / 2, shape.level - 0.012, surfaceWidth, 0.024))
        wine.fill(surface, with: .color(Color(uiColor: liquid.mixed(with: .white, amount: 0.38)).opacity(0.9)))

        if vessel == .flute {
            var random = SeededGenerator(string: seed)
            for _ in 0..<9 {
                let u = CGFloat(random.range(0.465, 0.535))
                let v = CGFloat(random.range(Double(shape.level) + 0.04, Double(shape.bottomY) - 0.05))
                let radius = CGFloat(random.range(0.004, 0.009))
                let bubble = Path(ellipseIn: frame.rect(u - radius, v - radius, radius * 2, radius * 2))
                context.fill(bubble, with: .color(.white.opacity(0.7)))
            }
        }

        // Стекло: лёгкая заливка, контур, ножка, основание и блик.
        let glassColor = Color.white.opacity(0.82)
        context.fill(bowl, with: .color(.white.opacity(0.06)))
        context.stroke(bowl, with: .color(glassColor), lineWidth: max(1, frame.side * 0.009))
        let stemWidth: CGFloat = 0.014
        context.fill(Path(roundedRect: frame.rect(0.5 - stemWidth / 2, shape.bottomY - 0.005, stemWidth,
                                                  0.865 - shape.bottomY),
                          cornerRadius: frame.side * 0.004),
                     with: .color(glassColor))
        context.fill(Path(ellipseIn: frame.rect(0.5 - shape.footWidth / 2, 0.85, shape.footWidth, 0.03)),
                     with: .color(glassColor))
        var shine = Path()
        shine.move(to: frame.point(shape.rimLeft + 0.035, shape.rimY + 0.05))
        shine.addQuadCurve(to: frame.point(shape.bulge + 0.06, shape.bulgeY + 0.12),
                           control: frame.point(shape.bulge + 0.015, shape.bulgeY))
        context.stroke(shine, with: .color(.white.opacity(0.42)),
                       style: StrokeStyle(lineWidth: max(1, frame.side * 0.014), lineCap: .round))
    }

    static func cup(in context: inout GraphicsContext, size: CGSize, liquid: UIColor, accent: UIColor,
                    light: UIColor, seed: String) {
        background(in: &context, size: size,
                   top: accent.mixed(with: .black, amount: 0.5), bottom: liquid.mixed(with: .black, amount: 0.72))
        let frame = Frame(size: size)

        // Блюдце.
        context.fill(Path(ellipseIn: frame.rect(0.09, 0.11, 0.84, 0.84)), with: .color(.black.opacity(0.25)))
        let saucer = Path(ellipseIn: frame.rect(0.08, 0.08, 0.84, 0.84))
        context.fill(saucer, with: .color(Color(uiColor: light.mixed(with: .white, amount: 0.35))))
        context.stroke(Path(ellipseIn: frame.rect(0.17, 0.17, 0.66, 0.66)),
                       with: .color(Color(uiColor: light.mixed(with: .black, amount: 0.12))),
                       lineWidth: max(1, frame.side * 0.006))

        // Ручка и чашка.
        context.fill(Path(roundedRect: frame.rect(0.74, 0.455, 0.13, 0.09), cornerRadius: frame.side * 0.045),
                     with: .color(.white))
        context.fill(Path(ellipseIn: frame.rect(0.205, 0.215, 0.6, 0.6)), with: .color(.black.opacity(0.18)))
        context.fill(Path(ellipseIn: frame.rect(0.2, 0.2, 0.6, 0.6)), with: .color(.white))

        // Чай: темнее к краям, светлее в центре.
        let tea = Path(ellipseIn: frame.rect(0.25, 0.25, 0.5, 0.5))
        context.fill(tea, with: .radialGradient(
            Gradient(colors: [Color(uiColor: liquid.mixed(with: .white, amount: 0.25)),
                              Color(uiColor: liquid.mixed(with: .black, amount: 0.2))]),
            center: frame.point(0.46, 0.46), startRadius: 0, endRadius: frame.side * 0.3))
        context.fill(Path(ellipseIn: frame.rect(0.33, 0.31, 0.13, 0.05)), with: .color(.white.opacity(0.3)))

        // Чаинка на блюдце — в случайном месте, но не под ручкой.
        var random = SeededGenerator(string: seed)
        let angle = random.range(0.65, 1.9) * Double.pi
        let distance = 0.385
        let center = frame.point(CGFloat(0.5 + cos(angle) * distance), CGFloat(0.5 + sin(angle) * distance))
        let length = frame.side * 0.1
        var leaf = Path()
        leaf.move(to: CGPoint(x: -length / 2, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: length / 2, y: 0), control: CGPoint(x: 0, y: -length * 0.42))
        leaf.addQuadCurve(to: CGPoint(x: -length / 2, y: 0), control: CGPoint(x: 0, y: length * 0.42))
        var vein = Path()
        vein.move(to: CGPoint(x: -length / 2, y: 0))
        vein.addLine(to: CGPoint(x: length * 0.38, y: 0))
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(angle + random.range(-0.6, 0.6)))
        context.fill(leaf.applying(transform), with: .color(Color(uiColor: accent.mixed(with: .black, amount: 0.15))))
        context.stroke(vein.applying(transform), with: .color(.white.opacity(0.45)),
                       lineWidth: max(0.5, frame.side * 0.004))
    }
}
