import CoreGraphics
import Foundation

struct RowInk {
    let costs: [Double]

    init(costs: [Double]) { self.costs = costs }

    init(image: CGImage) throws {
        let width = min(144, image.width)
        let height = min(12_000, image.height)
        var pixels = [UInt8](repeating: 255, count: width * height)
        let sampled = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let bitmap = CGContext(data: buffer.baseAddress, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: width,
                                         space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            bitmap.setFillColor(gray: 1, alpha: 1)
            bitmap.fill(rect)
            bitmap.interpolationQuality = .medium
            bitmap.draw(image, in: rect)
            return true
        }
        guard sampled else { throw ShotError.tooLarge }
        var raw = [Double](repeating: 0, count: height)
        for row in 0..<height {
            var edges = 0
            var horizontal = 0
            var ink = 0
            let start = row * width
            let left = Int(pixels[start])
            let right = Int(pixels[start + width - 1])
            for column in 1..<width {
                let position = start + column
                let value = Int(pixels[position])
                if abs(Int(pixels[position]) - Int(pixels[position - 1])) >= 25 { horizontal += 1 }
                if row > 0 && abs(Int(pixels[position]) - Int(pixels[position - width])) >= 30 { edges += 1 }
                if min(abs(value - left), abs(value - right)) >= 35 { ink += 1 }
            }
            raw[row] = (Double(horizontal) + Double(edges) * 0.6 + Double(ink) * 0.45) / Double(width)
        }
        costs = raw.indices.map { row in
            raw[max(0, row - 2)...min(height - 1, row + 2)].max() ?? 0
        }
    }

    func clear(at pixel: Int, sourceHeight: Int) -> Bool {
        guard !costs.isEmpty else { return false }
        let index = min(costs.count - 1, max(0, Int(Double(pixel) * Double(costs.count) / Double(sourceHeight))))
        return costs[index] < 0.025
    }

    func suggested(before limit: Int, window: Int, sourceHeight: Int) -> Int? {
        let step = max(1, sourceHeight / max(1, costs.count))
        let earliest = max(1, limit - window)
        guard earliest <= limit else { return nil }
        return stride(from: limit, through: earliest, by: -step).first { clear(at: $0, sourceHeight: sourceHeight) }
    }
}

struct LongSlice: Equatable {
    var start: Int
    var end: Int
}

struct PageCut: Identifiable, Equatable, Codable, Sendable {
    var id: Int
    var position: Int
    var minimum: Int
    var maximum: Int
    var overlap: Int
    var nextPage: Int
}

struct LongPlan {
    let slices: [LongSlice]
    let cuts: [PageCut]

    static func make(height: Int, capacity: Int, overlap: Int, ink: RowInk,
                     overrides: [Int: Int]) -> Self {
        var slices: [LongSlice] = []
        var cuts: [PageCut] = []
        var start = 0
        let capacity = max(2, capacity)
        while height - start > capacity {
            let limit = start + capacity
            let extra = min(max(0, overlap), capacity / 4)
            let minimum = start + max(1, capacity * 3 / 5)
            let maximum = limit - extra
            let manual = overrides[cuts.count].map { min(limit, max(minimum, $0)) }
            let suggested = ink.suggested(before: limit, window: capacity / 7, sourceHeight: height)
            let candidate = manual ?? suggested
            let clean = candidate.map { ink.clear(at: $0, sourceHeight: height) } ?? false
            let next = clean ? (candidate ?? limit) : min(maximum, candidate ?? maximum)
            let shared = clean ? 0 : extra
            slices.append(LongSlice(start: start, end: next + shared))
            cuts.append(PageCut(id: cuts.count, position: next, minimum: minimum,
                                maximum: limit, overlap: shared, nextPage: 0))
            start = next
        }
        if start < height { slices.append(LongSlice(start: start, end: height)) }
        return Self(slices: slices, cuts: cuts)
    }
}

struct Placement {
    let shot: Shot
    let slice: LongSlice?
    let target: CGRect
}

struct SplitRecord: Identifiable, Equatable, Codable, Sendable {
    let shot: Shot
    let firstPage: Int
    let cuts: [PageCut]
    var id: UUID { shot.id }
    var lastPage: Int { firstPage + cuts.count }
}

struct PagePlan {
    static let a4 = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let pointsPerMM: CGFloat = 72 / 25.4

    let pages: [[Placement]]
    let splits: [SplitRecord]
    let content: CGRect

    static func body(layout: Layout, pro: Bool) -> CGRect {
        let margin = CGFloat(layout.margin) * pointsPerMM
        let paper = a4.insetBy(dx: margin, dy: margin)
        let footer: CGFloat = (layout.numbers || layout.date || !pro) ? 19 : 0
        return CGRect(x: paper.minX, y: paper.minY, width: paper.width, height: paper.height - footer)
    }

    static func isLong(_ shot: Shot, layout: Layout, pro: Bool) -> Bool {
        guard shot.available else { return false }
        let content = body(layout: layout, pro: pro)
        return CGFloat(shot.height) * content.width > CGFloat(shot.width) * content.height
    }

    static func fit(_ size: CGSize, inside cell: CGRect) -> CGRect {
        let factor = min(cell.width / size.width, cell.height / size.height)
        let fitted = CGSize(width: size.width * factor, height: size.height * factor)
        return CGRect(x: cell.midX - fitted.width / 2, y: cell.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    static func make(shots: [Shot], layout: Layout, pro: Bool, cuts: [UUID: [Int: Int]],
                     analyze: (Shot) throws -> RowInk) throws -> Self {
        let content = body(layout: layout, pro: pro)
        let columns = layout.grid.columns
        let rows = layout.grid.rows
        let gutter: CGFloat = 8
        let width = (content.width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (content.height - gutter * CGFloat(rows - 1)) / CGFloat(rows)
        var pages: [[Placement]] = []
        var splits: [SplitRecord] = []
        var regular: [Placement] = []
        for shot in shots {
            try Task.checkCancellation()
            if layout.splitLong && isLong(shot, layout: layout, pro: pro) {
                if !regular.isEmpty {
                    pages.append(regular)
                    regular.removeAll(keepingCapacity: true)
                }
                let pixelsPerPoint = CGFloat(shot.width) / content.width
                let capacity = Int(content.height * pixelsPerPoint)
                guard capacity >= 2, shot.height / capacity <= 300 else { throw ShotError.tooLarge }
                let plan = LongPlan.make(height: shot.height, capacity: capacity,
                                         overlap: Int(8 * pointsPerMM * pixelsPerPoint),
                                         ink: try analyze(shot), overrides: cuts[shot.id] ?? [:])
                let firstPage = pages.count + 1
                let indexedCuts = plan.cuts.map { cut in
                    var copy = cut
                    copy.nextPage = firstPage + cut.id + 1
                    return copy
                }
                if !indexedCuts.isEmpty {
                    splits.append(SplitRecord(shot: shot, firstPage: firstPage, cuts: indexedCuts))
                }
                for slice in plan.slices {
                    let target = CGRect(x: content.minX, y: content.minY, width: content.width,
                                        height: min(content.height, CGFloat(slice.end - slice.start) / pixelsPerPoint))
                    pages.append([Placement(shot: shot, slice: slice, target: target)])
                }
            } else {
                let cell = CGRect(x: content.minX + CGFloat(regular.count % columns) * (width + gutter),
                                  y: content.minY + CGFloat(regular.count / columns) * (height + gutter),
                                  width: width, height: height)
                let target = fit(CGSize(width: shot.width, height: shot.height), inside: cell)
                regular.append(Placement(shot: shot, slice: nil, target: target))
                if regular.count == layout.grid.rawValue {
                    pages.append(regular)
                    regular.removeAll(keepingCapacity: true)
                }
            }
        }
        if !regular.isEmpty { pages.append(regular) }
        return Self(pages: pages, splits: splits, content: content)
    }
}
