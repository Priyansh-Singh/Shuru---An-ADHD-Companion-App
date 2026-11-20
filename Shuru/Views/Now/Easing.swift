import Foundation

/// Small timing helpers so the hold and celebration animations are plain functions of time.
enum Ease {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// CSS-style cubic-bezier(x1, y1, x2, y2) evaluated at progress x.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        let x = clamp(x)
        if x == 0 || x == 1 { return x }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<40 {
            s = (lo + hi) / 2
            let bx = 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s
            if bx < x { lo = s } else { hi = s }
        }
        return 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s
    }

    /// Fast at first, slowing near the end but still moving: the hold fill.
    static func hold(_ x: Double) -> Double { bezier(0.15, 0.6, 0.5, 0.85, x) }

    static func outCubic(_ x: Double) -> Double { let p = 1 - clamp(x); return 1 - p * p * p }
    static func inOut(_ x: Double) -> Double { bezier(0.4, 0, 0.3, 1, x) }

    /// Goes slightly the other way first, then accelerates: a rubber-band snap back.
    static func inBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        let t = clamp(x)
        return c3 * t * t * t - c1 * t * t
    }

    /// Linear interpolation across keyframes [(time, value)], with an ease on each segment.
    static func keyframes(_ t: Double, _ frames: [(Double, Double)], ease: (Double) -> Double = { $0 }) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 0..<(frames.count - 1) {
            let a = frames[i], b = frames[i + 1]
            if t >= a.0 && t <= b.0 {
                let p = b.0 == a.0 ? 1 : (t - a.0) / (b.0 - a.0)
                return a.1 + (b.1 - a.1) * ease(p)
            }
        }
        return last.1
    }
}
