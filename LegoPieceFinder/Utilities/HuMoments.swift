import Foundation
import simd

/// Computes the 7 Hu moment invariants from a set of 2D points (contour).
/// These invariants are translation-, scale-, and rotation-invariant.
enum HuMoments {

    /// Computes 7 Hu moment invariants from contour points.
    /// Points should be in any consistent coordinate system.
    static func compute(from points: [SIMD2<Float>]) -> [Double] {
        guard points.count >= 3 else { return Array(repeating: 0, count: 7) }

        let n = Double(points.count)

        // Raw moments m_pq = Σ x^p * y^q
        var m00 = 0.0, m10 = 0.0, m01 = 0.0
        var m20 = 0.0, m11 = 0.0, m02 = 0.0
        var m30 = 0.0, m21 = 0.0, m12 = 0.0, m03 = 0.0

        for p in points {
            let x = Double(p.x)
            let y = Double(p.y)
            m00 += 1
            m10 += x
            m01 += y
            m20 += x * x
            m11 += x * y
            m02 += y * y
            m30 += x * x * x
            m21 += x * x * y
            m12 += x * y * y
            m03 += y * y * y
        }

        // Centroid
        let cx = m10 / m00
        let cy = m01 / m00

        // Central moments μ_pq = Σ (x - cx)^p * (y - cy)^q
        var mu20 = 0.0, mu11 = 0.0, mu02 = 0.0
        var mu30 = 0.0, mu21 = 0.0, mu12 = 0.0, mu03 = 0.0

        for p in points {
            let dx = Double(p.x) - cx
            let dy = Double(p.y) - cy
            mu20 += dx * dx
            mu11 += dx * dy
            mu02 += dy * dy
            mu30 += dx * dx * dx
            mu21 += dx * dx * dy
            mu12 += dx * dy * dy
            mu03 += dy * dy * dy
        }

        // Normalized central moments η_pq = μ_pq / μ_00^((p+q)/2 + 1)
        let mu00 = m00
        let eta20 = mu20 / pow(mu00, 2)
        let eta11 = mu11 / pow(mu00, 2)
        let eta02 = mu02 / pow(mu00, 2)
        let eta30 = mu30 / pow(mu00, 2.5)
        let eta21 = mu21 / pow(mu00, 2.5)
        let eta12 = mu12 / pow(mu00, 2.5)
        let eta03 = mu03 / pow(mu00, 2.5)

        // 7 Hu moment invariants
        let h1 = eta20 + eta02
        let h2 = pow(eta20 - eta02, 2) + 4 * pow(eta11, 2)
        let h3 = pow(eta30 - 3 * eta12, 2) + pow(3 * eta21 - eta03, 2)
        let h4 = pow(eta30 + eta12, 2) + pow(eta21 + eta03, 2)
        let h5 = (eta30 - 3 * eta12) * (eta30 + eta12) * (pow(eta30 + eta12, 2) - 3 * pow(eta21 + eta03, 2))
            + (3 * eta21 - eta03) * (eta21 + eta03) * (3 * pow(eta30 + eta12, 2) - pow(eta21 + eta03, 2))
        let h6 = (eta20 - eta02) * (pow(eta30 + eta12, 2) - pow(eta21 + eta03, 2))
            + 4 * eta11 * (eta30 + eta12) * (eta21 + eta03)
        let h7 = (3 * eta21 - eta03) * (eta30 + eta12) * (pow(eta30 + eta12, 2) - 3 * pow(eta21 + eta03, 2))
            - (eta30 - 3 * eta12) * (eta21 + eta03) * (3 * pow(eta30 + eta12, 2) - pow(eta21 + eta03, 2))

        return [h1, h2, h3, h4, h5, h6, h7]
    }

    /// Log-scale distance between two Hu moment vectors.
    /// Lower is more similar. Standard approach for Hu moment comparison.
    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == 7, b.count == 7 else { return .infinity }
        var sum = 0.0
        for i in 0..<7 {
            let sa = a[i] == 0 ? 0 : copysign(1, a[i]) * log10(abs(a[i]))
            let sb = b[i] == 0 ? 0 : copysign(1, b[i]) * log10(abs(b[i]))
            sum += abs(sa - sb)
        }
        return sum
    }
}
