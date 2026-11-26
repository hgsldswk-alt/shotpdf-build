import SwiftUI

enum Theme {
    static let accent = Color(red: 52 / 255, green: 96 / 255, blue: 127 / 255)
    static let amber = Color(red: 233 / 255, green: 162 / 255, blue: 59 / 255)
    static let green = Color(red: 111 / 255, green: 165 / 255, blue: 140 / 255)
    static let background = Color(red: 246 / 255, green: 247 / 255, blue: 249 / 255)
    static let ink = Color(red: 35 / 255, green: 39 / 255, blue: 46 / 255)
    static let muted = Color(red: 77 / 255, green: 91 / 255, blue: 106 / 255)
    static let blueWash = Color(red: 231 / 255, green: 239 / 255, blue: 244 / 255)
    static let amberWash = Color(red: 253 / 255, green: 239 / 255, blue: 214 / 255)
    static let greenWash = Color(red: 225 / 255, green: 239 / 255, blue: 232 / 255)
    static let amberInk = Color(red: 111 / 255, green: 68 / 255, blue: 14 / 255)
    static let greenInk = Color(red: 41 / 255, green: 88 / 255, blue: 71 / 255)
    static let line = Color(red: 213 / 255, green: 224 / 255, blue: 233 / 255)
    static let stage = Color(red: 229 / 255, green: 235 / 255, blue: 239 / 255)
}

enum Tone {
    case blue, amber, green
    var wash: Color {
        switch self {
        case .blue: Theme.blueWash
        case .amber: Theme.amberWash
        case .green: Theme.greenWash
        }
    }
    var ink: Color {
        switch self {
        case .blue: Theme.accent
        case .amber: Theme.amberInk
        case .green: Theme.greenInk
        }
    }
}

extension View {
    func panel(_ fill: Color = .white, radius: CGFloat = 18, shadow: Bool = true) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line, lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: Theme.ink.opacity(shadow ? 0.07 : 0), radius: 12, x: 0, y: 4)
    }
}

struct StatusPill: View {
    let title: String
    var tone: Tone = .blue

    var body: some View {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tone.ink)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(tone.wash, in: Capsule())
    }
}

struct IconBox: View {
    let symbol: String
    var tone: Tone = .blue

    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            .frame(width: 38, height: 38)
            .foregroundStyle(tone.ink)
            .background(tone.wash, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    enum Kind { case primary, secondary, white }
    let title: String
    let symbol: String
    let id: String
    var kind: Kind = .primary
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: kind == .primary ? 52 : 44)
                .foregroundStyle(kind == .primary ? .white : Theme.accent)
                .background(kind == .primary ? Theme.accent : (kind == .white ? .white : Theme.blueWash),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if kind == .white {
                        RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line).allowsHitTesting(false)
                    }
                }
                .opacity(enabled ? 1 : 0.52)
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

struct IconTile: View {
    let title: String
    let symbol: String
    let id: String
    var tone: Tone = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                IconBox(symbol: symbol, tone: tone)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .padding(13).panel()
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

struct IconRow: View {
    let title: String
    let symbol: String
    var tone: Tone = .blue
    var subtitle: String?
    var value: String?

    var body: some View {
        HStack(spacing: 10) {
            IconBox(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 5)
            if let value { Text(value).font(.caption.weight(.medium)).foregroundStyle(Theme.accent) }
        }
    }
}

struct RowButton: View {
    let title: String
    let symbol: String
    let id: String
    var tone: Tone = .blue
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconRow(title: title, symbol: symbol, tone: tone, value: value)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

struct EmptyIllustration: View {
    var body: some View {
        ZStack {
            sheet("photo.on.rectangle", width: 82, height: 104, color: Theme.stage, tone: .blue)
                .rotationEffect(.degrees(-15)).offset(x: -64, y: 20)
            sheet("square.grid.2x2", width: 106, height: 139, color: .white, tone: .blue, a4: true)
                .rotationEffect(.degrees(8)).offset(x: 3, y: -6)
            sheet("doc.text", width: 66, height: 83, color: Theme.amberWash, tone: .amber)
                .rotationEffect(.degrees(12)).offset(x: 80, y: 28)
        }
        .frame(maxWidth: .infinity).frame(height: 185).accessibilityHidden(true)
    }

    private func sheet(_ symbol: String, width: CGFloat, height: CGFloat, color: Color,
                       tone: Tone, a4: Bool = false) -> some View {
        ZStack(alignment: .bottom) {
            Image(systemName: symbol)
                .font(.system(size: a4 ? 41 : 27, weight: .medium))
                .frame(width: width, height: height)
            if a4 {
                Text("A4").font(.system(.caption2, design: .rounded, weight: .bold)).padding(.bottom, 10)
            }
        }
        .foregroundStyle(tone.ink).panel(color, radius: 12)
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EmptyIllustration()
            Text(L.t("home.hero")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Text(L.t("home.detail")).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            content.padding(.top, 6)
        }
        .padding(19).panel(Theme.blueWash)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    let id: String
    var subtitle: String?
    var back: (() -> Void)?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .accessibilityLabel(L.t("action.back")).accessibilityIdentifier(id + ".back")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier(id + ".title")
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 44)
    }
}

struct Callout: View {
    let text: String
    var tone: Tone = .amber
    var icon = "info.circle"

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption).foregroundStyle(tone.ink)
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.wash, in: RoundedRectangle(cornerRadius: 11))
            .fixedSize(horizontal: false, vertical: true)
    }
}
