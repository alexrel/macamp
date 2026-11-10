import Foundation
import CoreGraphics

public struct SkinRegion {
    public var normalMask: CGPath?
    public var windowShadeMask: CGPath?
    public var equalizerMask: CGPath?
    public var equalizerShadeMask: CGPath?

    func normalMask(fitting size: CGSize) -> CGPath? {
        guard let normalMask else { return nil }
        let path = CGMutablePath()
        // Stretch the middle of the player outline while keeping the skin's corner cutouts at their original size.
        func stretch(_ coordinate: CGFloat, from source: CGFloat, to target: CGFloat) -> CGFloat {
            let corner = min(source, target) / 4
            let fraction = (coordinate - corner) / (source - 2 * corner)
            return coordinate + (target - source) * min(1, max(0, fraction))
        }
        normalMask.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .closeSubpath {
                path.closeSubpath()
                return
            }
            let point = element.points[0]
            let fitted = CGPoint(x: stretch(point.x, from: AppConstants.Window.width, to: size.width),
                                 y: stretch(point.y, from: AppConstants.Window.height, to: size.height))
            if element.type == .moveToPoint {
                path.move(to: fitted)
            } else {
                path.addLine(to: fitted)
            }
        }
        return path
    }
}

public class RegionParser {
    public static func parse(text: String) -> SkinRegion {
        var sections: [String: (numPointsStr: String, pointListStr: String)] = [:]
        var currentSection: String? = nil
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }
            
            if trimmed.hasPrefix("[") && trimmed.contains("]") {
                if let closeIdx = trimmed.firstIndex(of: "]") {
                    let secName = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    currentSection = secName
                    if sections[secName] == nil {
                        sections[secName] = ("", "")
                    }
                }
                continue
            }
            
            guard let cur = currentSection, trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            
            let key = parts[0].lowercased()
            // Strip any trailing comments (e.g., "; do this last")
            var val = parts[1]
            if let commentIdx = val.firstIndex(where: { $0 == ";" || $0 == "#" }) {
                val = String(val[..<commentIdx]).trimmingCharacters(in: .whitespaces)
            }
            
            var existing = sections[cur] ?? ("", "")
            if key == "numpoints" {
                existing.numPointsStr = val
            } else if key == "pointlist" {
                if existing.pointListStr.isEmpty {
                    existing.pointListStr = val
                } else {
                    existing.pointListStr += " " + val
                }
            }
            sections[cur] = existing
        }
        
        func buildPath(from entry: (numPointsStr: String, pointListStr: String)?) -> CGPath? {
            guard let entry = entry, !entry.numPointsStr.isEmpty, !entry.pointListStr.isEmpty else {
                return nil
            }
            
            let pointCounts = entry.numPointsStr
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            
            // Extract all coordinate numbers from pointlist:
            let tokens = entry.pointListStr
                .replacingOccurrences(of: ",", with: " ")
                .split(separator: " ")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            
            guard tokens.count >= 2 else { return nil }
            
            var points: [CGPoint] = []
            for i in stride(from: 0, to: tokens.count - 1, by: 2) {
                points.append(CGPoint(x: tokens[i], y: tokens[i + 1]))
            }
            
            let mutablePath = CGMutablePath()
            var pointIndex = 0
            var addedAny = false
            
            for count in pointCounts {
                guard count >= 3, pointIndex + count <= points.count else {
                    pointIndex += count
                    continue
                }
                
                let subPoints = points[pointIndex..<(pointIndex + count)]
                pointIndex += count
                
                guard let first = subPoints.first else { continue }
                mutablePath.move(to: first)
                for pt in subPoints.dropFirst() {
                    mutablePath.addLine(to: pt)
                }
                mutablePath.closeSubpath()
                addedAny = true
            }
            
            return addedAny ? mutablePath : nil
        }
        
        var region = SkinRegion()
        region.normalMask = buildPath(from: sections["normal"])
        region.windowShadeMask = buildPath(from: sections["windowshade"])
        region.equalizerMask = buildPath(from: sections["equalizer"])
        region.equalizerShadeMask = buildPath(from: sections["equalizerws"] ?? sections["equalizerwindowshade"])
        
        return region
    }
}
