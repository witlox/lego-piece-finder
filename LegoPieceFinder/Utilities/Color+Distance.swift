import UIKit

struct CIELABColor: Sendable {
    let L: CGFloat
    let a: CGFloat
    let b: CGFloat
}

extension CIELABColor {
    static func from(rgb color: UIColor) -> CIELABColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        // sRGB → linear
        func linearize(_ c: CGFloat) -> CGFloat {
            c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }
        let lr = linearize(r)
        let lg = linearize(g)
        let lb = linearize(b)

        // Linear RGB → XYZ (D65)
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047
        let y = (0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb) / 1.00000
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883

        // XYZ → CIELAB
        func f(_ t: CGFloat) -> CGFloat {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (903.3 * t + 16.0) / 116.0
        }
        let fx = f(x)
        let fy = f(y)
        let fz = f(z)

        return CIELABColor(
            L: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    func distance(to other: CIELABColor) -> CGFloat {
        let dL = L - other.L
        let da = a - other.a
        let db = b - other.b
        return sqrt(dL * dL + da * da + db * db)
    }
}
