import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    init(hex: String, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(opacity)))
    }

    /// A color that changes with light and dark mode.
    static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

struct OrbColors {
    let c1: Color
    let c2: Color
    let c3: Color
    let glow: Color
}

enum Theme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let card2 = Color(.tertiarySystemGroupedBackground)
    static let checkbox = Color.dynamic(light: "#8E8E93", dark: "#6C6C70")
    static let danger = Color.dynamic(light: "#D70015", dark: "#FF6961")

    static func accent(_ p: Palette) -> Color {
        switch p {
        case .ember: return .dynamic(light: "#B4441F", dark: "#F0784A")
        case .lagoon: return .dynamic(light: "#0B7A78", dark: "#2CC4BF")
        case .dusk: return .dynamic(light: "#6A3FD6", dark: "#A98BFF")
        }
    }

    static func onAccent(_ dark: Bool) -> Color {
        dark ? Color(hex: "#141417") : .white
    }

    static func orb(_ p: Palette, dark: Bool) -> OrbColors {
        switch (p, dark) {
        case (.ember, true):
            return OrbColors(c1: Color(hex: "#E4572E"), c2: Color(hex: "#B8336A"), c3: Color(hex: "#E9852A"), glow: Color(hex: "#E4572E", opacity: 0.26))
        case (.ember, false):
            return OrbColors(c1: Color(hex: "#FFB199"), c2: Color(hex: "#FFA3C0"), c3: Color(hex: "#FFD08A"), glow: Color(hex: "#FF966E", opacity: 0.32))
        case (.lagoon, true):
            return OrbColors(c1: Color(hex: "#0E9C9C"), c2: Color(hex: "#2563EB"), c3: Color(hex: "#0F9F8F"), glow: Color(hex: "#0E9C9C", opacity: 0.26))
        case (.lagoon, false):
            return OrbColors(c1: Color(hex: "#8EE3DC"), c2: Color(hex: "#A3C2FF"), c3: Color(hex: "#B4EFD6"), glow: Color(hex: "#6EC8D2", opacity: 0.32))
        case (.dusk, true):
            return OrbColors(c1: Color(hex: "#7C3AED"), c2: Color(hex: "#C0266E"), c3: Color(hex: "#4F46E5"), glow: Color(hex: "#7C3AED", opacity: 0.28))
        case (.dusk, false):
            return OrbColors(c1: Color(hex: "#CDB9FF"), c2: Color(hex: "#FFB6DA"), c3: Color(hex: "#AFC8FF"), glow: Color(hex: "#AA8CFF", opacity: 0.32))
        }
    }

    /// Text drawn over the orb.
    static func orbSub(_ dark: Bool) -> Color { dark ? Color(hex: "#E4DED5") : Color(hex: "#45423C") }
}

// MARK: - Shared building blocks

struct Card<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0)
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TypeDot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A page that scrolls and leaves room for the page dots at the bottom.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }
}

struct CheckCircle: View {
    let done: Bool
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? tint : Theme.checkbox, lineWidth: 1.6)
                .background(Circle().fill(done ? tint : .clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

struct FloatingAddButton: View {
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .accessibilityLabel(label)
        .padding(.trailing, 20)
        .padding(.bottom, 92)
    }
}

struct Toast: View {
    let text: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.trailing, actionLabel == nil ? 10 : 0)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(Theme.card2, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.bottom, 96)
    }
}
