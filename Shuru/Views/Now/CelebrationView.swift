import SwiftUI

/// The tick, sparkles and rings after finishing something. Everything is a function of `t` (seconds).
struct CelebrationView: View {
    let t: Double
    let label: String
    let style: CelebrationStyle
    let palette: Palette
    let dark: Bool

    private static let twinkleSpots: [(x: Double, y: Double, size: Double)] = [
        (46, -40, 18), (-50, -28, 13), (60, 8, 11), (-58, 18, 15),
        (12, -64, 12), (-24, -60, 9), (36, 38, 10), (-38, 42, 11)
    ]

    var body: some View {
        let orb = Theme.orb(palette, dark: dark)
        let colors: [Color] = dark ? [.white, orb.c1, Color(hex: "#FFF1D6"), orb.c2, orb.c3] : [Theme.accent(palette), orb.c1, orb.c2, orb.c3]
        ZStack {
            if style == .ripple {
                ring(delay: 0.08, width: 2)
                ring(delay: 0.22, width: 1.5)
            }
            if style == .sparks {
                ForEach(0..<12, id: \.self) { k in
                    burstDot(k, color: colors[k % colors.count])
                }
            }
            ForEach(0..<Self.twinkleSpots.count, id: \.self) { i in
                twinkle(i, color: colors[i % colors.count])
            }
            tick
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(Theme.orbSub(dark))
                    .fixedSize()
                    .offset(y: 70 + labelLift)
                    .opacity(labelOpacity)
            }
        }
        .frame(width: 300, height: 300)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Tick: pops in a bit too big, settles once, fades at the end.

    private var tick: some View {
        let p = t - 0.04
        let d = 2.0
        let x = p / d
        let scale = Ease.keyframes(x, [(0, 0.3), (0.18, 1.22), (0.38, 1)], ease: Ease.inOut)
        let rot = Ease.keyframes(x, [(0, -12), (0.18, 3), (0.38, 0)], ease: Ease.inOut)
        let opacity = Ease.keyframes(x, [(0, 0), (0.18, 1), (0.86, 1), (1, 0)])
        let draw = Ease.outCubic((t - 0.2) / 0.52)
        return TickShape()
            .trim(from: 0, to: CGFloat(draw))
            .stroke(Color.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .frame(width: 72, height: 72)
            .shadow(color: dark ? .black.opacity(0.45) : .white.opacity(0.8), radius: 12)
            .scaleEffect(CGFloat(scale))
            .rotationEffect(.degrees(rot))
            .opacity(p < 0 ? 0 : opacity)
    }

    private var labelOpacity: Double {
        let x = (t - 0.32) / 2.0
        return Ease.keyframes(x, [(0, 0), (0.3, 1), (0.75, 1), (1, 0)])
    }

    private var labelLift: Double {
        let x = (t - 0.32) / 2.0
        return Ease.keyframes(x, [(0, 6), (0.3, 0)])
    }

    // MARK: Sparkles near the tick

    private func twinkle(_ i: Int, color: Color) -> some View {
        let spot = Self.twinkleSpots[i]
        let delay = 0.18 + Double(i) * 0.085
        let dur = 0.9 + Double(i % 3) * 0.14
        let x = (t - delay) / dur
        let scale = Ease.keyframes(x, [(0, 0), (0.35, 1.2), (0.65, 0.8), (1, 0)])
        let opacity = Ease.keyframes(x, [(0, 0), (0.35, 1), (0.65, 0.9), (1, 0)])
        let rot = Ease.keyframes(x, [(0, 0), (0.35, 60), (0.65, 100), (1, 150)])
        return SparkleShape()
            .fill(color)
            .frame(width: spot.size, height: spot.size)
            .scaleEffect(CGFloat(scale))
            .rotationEffect(.degrees(rot))
            .opacity(x < 0 ? 0 : opacity)
            .offset(x: spot.x, y: spot.y)
    }

    // MARK: Ripple rings

    private func ring(delay: Double, width: CGFloat) -> some View {
        let x = (t - delay) / 0.76
        let scale = Ease.keyframes(x, [(0, 0.55), (1, 1.6)], ease: { Ease.bezier(0.2, 0.7, 0.2, 1, $0) })
        let opacity = Ease.keyframes(x, [(0, 0), (0.15, 0.75), (1, 0)])
        return Circle()
            .strokeBorder(dark ? Color(hex: "#F5F2EC", opacity: 0.55) : Color(hex: "#17161A", opacity: 0.35), lineWidth: width)
            .frame(width: 300, height: 300)
            .scaleEffect(CGFloat(scale))
            .opacity(x < 0 ? 0 : opacity)
    }

    // MARK: Sparks flying out

    private func burstDot(_ k: Int, color: Color) -> some View {
        let size: CGFloat = [6, 8, 5][k % 3]
        let angle = Double(k * 30 + (k % 2 == 1 ? 9 : -7))
        let delay = 0.06 + Double(k % 3) * 0.03
        let dur = 0.76 + Double(k % 4) * 0.05
        let x = (t - delay) / dur
        let dist = Ease.keyframes(x, [(0, 55), (1, 175)], ease: { Ease.bezier(0.15, 0.7, 0.3, 1, $0) })
        let scale = Ease.keyframes(x, [(0, 0.4), (1, 0)])
        let opacity = Ease.keyframes(x, [(0, 0), (0.2, 1), (1, 0)])
        let rad = (angle - 90) * .pi / 180
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(scale))
            .opacity(x < 0 ? 0 : opacity)
            .offset(x: CGFloat(cos(rad) * dist), y: CGFloat(sin(rad) * dist))
    }
}

struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 5 * s, y: 12.5 * s))
        p.addLine(to: CGPoint(x: 9.5 * s, y: 17 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 7.5 * s))
        return p
    }
}

/// Four-pointed sparkle.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy), control: CGPoint(x: cx + w * 0.08, y: cy - h * 0.08))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY), control: CGPoint(x: cx + w * 0.08, y: cy + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: cy), control: CGPoint(x: cx - w * 0.08, y: cy + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), control: CGPoint(x: cx - w * 0.08, y: cy - h * 0.08))
        p.closeSubpath()
        return p
    }
}
