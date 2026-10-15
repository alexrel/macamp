import Foundation
import CoreGraphics

public enum CubicSpline {
    /// Computes y values for integer x from 0 up to xs.last using natural cubic spline.
    public static func compute(xs: [Double], ys: [Double]) -> [Double] {
        guard xs.count == ys.count, xs.count >= 2 else { return ys }
        let n = xs.count - 1
        let maxX = Int(xs[n])
        guard maxX >= 0 else { return [] }
        
        let ks = getNaturalKs(xs: xs, ys: ys)
        var allYs: [Double] = []
        allYs.reserveCapacity(maxX + 1)
        
        var i = 1
        for x in 0...maxX {
            let xd = Double(x)
            while i < xs.count && xs[i] < xd {
                i += 1
            }
            if i >= xs.count { i = xs.count - 1 }
            let xDiff = xs[i] - xs[i - 1]
            let t = xDiff > 0 ? (xd - xs[i - 1]) / xDiff : 0.0
            let a = ks[i - 1] * xDiff - (ys[i] - ys[i - 1])
            let b = -ks[i] * xDiff + (ys[i] - ys[i - 1])
            let q = (1.0 - t) * ys[i - 1] + t * ys[i] + t * (1.0 - t) * (a * (1.0 - t) + b * t)
            allYs.append(q)
        }
        return allYs
    }
    
    private static func getNaturalKs(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count - 1
        var matrix = Array(repeating: Array(repeating: 0.0, count: n + 2), count: n + 1)
        
        for i in 1..<n {
            let dx0 = xs[i] - xs[i - 1]
            let dx1 = xs[i + 1] - xs[i]
            matrix[i][i - 1] = 1.0 / dx0
            matrix[i][i] = 2.0 * (1.0 / dx0 + 1.0 / dx1)
            matrix[i][i + 1] = 1.0 / dx1
            matrix[i][n + 1] = 3.0 * ((ys[i] - ys[i - 1]) / (dx0 * dx0) + (ys[i + 1] - ys[i]) / (dx1 * dx1))
        }
        
        let dx0 = xs[1] - xs[0]
        matrix[0][0] = 2.0 / dx0
        matrix[0][1] = 1.0 / dx0
        matrix[0][n + 1] = 3.0 * (ys[1] - ys[0]) / (dx0 * dx0)
        
        let dxn = xs[n] - xs[n - 1]
        matrix[n][n - 1] = 1.0 / dxn
        matrix[n][n] = 2.0 / dxn
        matrix[n][n + 1] = 3.0 * (ys[n] - ys[n - 1]) / (dxn * dxn)
        
        return solve(matrix: matrix)
    }
    
    private static func solve(matrix: [[Double]]) -> [Double] {
        var m = matrix
        let rowCount = m.count
        for k in 0..<rowCount {
            var iMax = k
            var valMax = -Double.infinity
            for i in k..<rowCount {
                if m[i][k] > valMax {
                    iMax = i
                    valMax = m[i][k]
                }
            }
            m.swapAt(k, iMax)
            
            for i in (k + 1)..<rowCount {
                let factor = abs(m[k][k]) > 1e-12 ? m[i][k] / m[k][k] : 0.0
                for j in (k + 1)...rowCount {
                    m[i][j] -= factor * m[k][j]
                }
                m[i][k] = 0.0
            }
        }
        
        var ks = Array(repeating: 0.0, count: rowCount)
        for i in stride(from: rowCount - 1, through: 0, by: -1) {
            let v = abs(m[i][i]) > 1e-12 ? m[i][rowCount] / m[i][i] : 0.0
            ks[i] = v
            for j in stride(from: i - 1, through: 0, by: -1) {
                m[j][rowCount] -= m[j][i] * v
                m[j][i] = 0.0
            }
        }
        return ks
    }
}
