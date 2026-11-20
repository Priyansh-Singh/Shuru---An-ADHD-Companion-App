import SwiftUI

/// Orb time that only moves forward while the orb is on screen, in small steps,
/// so coming back to Now continues the motion instead of jumping ahead.
final class OrbClock {
    private var t: Double = Double.random(in: 0..<600)
    private var last: Date?

    /// Only moves forward. A late frame still gets its real time (up to 1/15 s), so the motion stays even;
    /// a long gap (the page was hidden) doesn't make the orb jump.
    func time(at date: Date, speed: Double) -> Double {
        if let last {
            let dt = date.timeIntervalSince(last)
            guard dt > 0 else { return t }
            t += min(dt, 1.0 / 15.0) * speed
        }
        last = date
        return t
    }
}

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
        // A soft edge drawn as a gradient (the falloff of a Gaussian blur), so nothing is blurred per frame.
        let sigma = max(0.5, Double(blur))
        let r = (w + h) / 4
        return Rectangle()
            .fill(EllipticalGradient(gradient: OrbBlob.gradient(color: color, radius: r, sigma: sigma),
                                     center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: CGFloat(w + 6 * sigma), height: CGFloat(h + 6 * sigma))
            .rotationEffect(.radians(angle * 0.5))
            .offset(x: CGFloat(x), y: CGFloat(y))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Edge brightness at a distance from the edge, in standard deviations (½·erfc).
    private static let falloff: [(d: Double, a: Double)] = [
        (-2.5, 0.994), (-2, 0.977), (-1.5, 0.933), (-1, 0.841), (-0.5, 0.691), (0, 0.5),
        (0.5, 0.309), (1, 0.159), (1.5, 0.067), (2, 0.023), (2.5, 0.006), (3, 0),
    ]

    static func gradient(color: Color, radius r: Double, sigma: Double) -> Gradient {
        let outer = r + 3 * sigma
        var stops = [Gradient.Stop(color: color, location: 0)]
        for p in falloff {
            let loc = (r + p.d * sigma) / outer
            guard loc > 0 else { continue }
            stops.append(Gradient.Stop(color: color.opacity(p.a), location: min(1, loc)))
        }
        return Gradient(stops: stops)
    }
}
