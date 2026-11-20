import SwiftUI

/// The soft, slowly moving orb behind the next task. `time` drives the motion.
struct OrbView: View {
    let colors: OrbColors
    let dark: Bool
    let blur: CGFloat
    let time: Double

    var body: some View {
        let breathe = 0.995 + 0.045 * sin(time * 2 * .pi / 7)
        let opacity = dark ? 0.72 : 0.85
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors.glow, colors.glow.opacity(0)], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
            OrbBlob(color: colors.c1, size: 230, offset: CGPoint(x: -41, y: -37), period: 22, morph: 11, time: time, blur: blur)
                .opacity(opacity)
            OrbBlob(color: colors.c2, size: 210, offset: CGPoint(x: 47, y: 27), period: -28, morph: 13, time: time, blur: blur)
                .opacity(opacity)
            OrbBlob(color: colors.c3, size: 180, offset: CGPoint(x: -20, y: 60), period: 17, morph: 9, time: time, blur: max(0, blur - 2))
                .opacity(opacity)
        }
        .frame(width: 340, height: 340)
        .scaleEffect(breathe)
        .accessibilityHidden(true)
    }
}

private struct OrbBlob: View {
    let color: Color
    let size: CGFloat
    let offset: CGPoint
    let period: Double
    let morph: Double
    let time: Double
    let blur: CGFloat

    var body: some View {
        let angle: Double = time / period * 2 * .pi
        let ox = Double(offset.x), oy = Double(offset.y)
        let x: Double = ox * cos(angle) - oy * sin(angle)
        let y: Double = ox * sin(angle) + oy * cos(angle)
        let m: Double = sin(time * 2 * .pi / morph)
        let w = Double(size) * (1 + 0.06 * m)
        let h = Double(size) * (1 - 0.06 * m)
        return Ellipse()
            .fill(color)
            .frame(width: CGFloat(w), height: CGFloat(h))
            .rotationEffect(.radians(angle * 0.5))
            .blur(radius: blur)
            .offset(x: CGFloat(x), y: CGFloat(y))
    }
}
