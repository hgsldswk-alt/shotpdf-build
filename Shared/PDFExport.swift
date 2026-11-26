import Foundation
import PDFKit
import UIKit

struct RenderRequest: Equatable, Sendable {
    let shots: [Shot]
    let layout: Layout
    let quality: PDFQuality
    let cuts: [UUID: [Int: Int]]
    let pro: Bool
    let localDay: Date
}

struct PDFResult: Codable, Sendable {
    var url: URL
    let pageCount: Int
    let byteCount: Int
    let sourceCount: Int
    let splits: [SplitRecord]

    var size: String { ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file) }
}

enum PDFExport {
    static func make(_ request: RenderRequest, workspace: Workspace) throws -> PDFResult {
        guard !request.shots.isEmpty else { throw ShotError.noImages }
        try workspace.checkSpace(8 * 1024 * 1024)
        let directory = workspace.output.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let plan = try PagePlan.make(shots: request.shots, layout: request.layout,
                                         pro: request.pro, cuts: request.cuts) { shot in
                try autoreleasepool {
                    try RowInk(image: ImageFiles.renderImage(workspace.source(shot.id), width: shot.width,
                                                             height: shot.height, targetWidth: 450))
                }
            }
            let stage = directory.appendingPathComponent(".writing.pdf")
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [kCGPDFContextCreator as String: "ShotPDF"]
            let renderer = UIGraphicsPDFRenderer(bounds: PagePlan.a4, format: format)
            var renderError: Error?
            var lastLong: (UUID, CGImage)?
            try renderer.writePDF(to: stage) { context in
                for (index, page) in plan.pages.enumerated() {
                    if renderError != nil { break }
                    do {
                        try Task.checkCancellation()
                        try autoreleasepool {
                            context.beginPage()
                            UIColor.white.setFill()
                            context.fill(PagePlan.a4)
                            for item in page {
                                try autoreleasepool {
                                    let image = try image(for: item, request: request, workspace: workspace,
                                                          cachedLong: &lastLong)
                                    UIImage(cgImage: image).draw(in: item.target)
                                }
                            }
                            drawFooter(request, content: plan.content, page: index + 1)
                        }
                    } catch { renderError = error }
                }
            }
            if let renderError { throw renderError }
            try Task.checkCancellation()
            let expected = plan.pages.count
            let bytes = try stage.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, let document = PDFDocument(url: stage), document.pageCount == expected,
                  (0..<expected).allSatisfy({ index in
                      guard let box = document.page(at: index)?.bounds(for: .mediaBox) else { return false }
                      return abs(box.width - PagePlan.a4.width) < 0.05 && abs(box.height - PagePlan.a4.height) < 0.05
                  }) else { throw ShotError.pdf }
            let result = directory.appendingPathComponent(defaultName(date: request.localDay))
            try FileManager.default.moveItem(at: stage, to: result)
            return PDFResult(url: result, pageCount: expected, byteCount: bytes,
                             sourceCount: request.shots.count, splits: plan.splits)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func image(for item: Placement, request: RenderRequest, workspace: Workspace,
                              cachedLong: inout (UUID, CGImage)?) throws -> CGImage {
        let shot = item.shot
        let compact = request.quality == .compact
        let pixelsPerPoint: CGFloat = compact ? 1.65 : 4.2
        let targetWidth = min(shot.width, max(1, Int(ceil(item.target.width * pixelsPerPoint))))
        let source: CGImage
        if item.slice != nil, let cachedLong, cachedLong.0 == shot.id {
            source = cachedLong.1
        } else {
            cachedLong = nil
            source = try ImageFiles.renderImage(workspace.source(shot.id), width: shot.width,
                                                height: shot.height, targetWidth: targetWidth)
            if item.slice != nil { cachedLong = (shot.id, source) }
        }
        let portion: CGImage
        if let slice = item.slice {
            let scale = Double(source.height) / Double(shot.height)
            let top = min(source.height - 1, Int(floor(Double(slice.start) * scale)))
            let bottom = min(source.height, Int(ceil(Double(slice.end) * scale)))
            guard let cropped = source.cropping(to: CGRect(x: 0, y: top, width: source.width,
                                                           height: max(1, bottom - top))) else { throw ShotError.pdf }
            portion = cropped
        } else {
            portion = source
        }
        guard compact else { return portion }
        let data = try ImageFiles.jpeg(portion, quality: 0.66)
        guard let jpeg = UIImage(data: data)?.cgImage else { throw ShotError.pdf }
        return jpeg
    }

    private static func drawFooter(_ request: RenderRequest, content: CGRect, page: Int) {
        let ink = UIColor(red: 52 / 255, green: 96 / 255, blue: 127 / 255, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: ink]
        let y = content.maxY + 6
        if request.layout.date {
            (L.date(request.localDay) as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: attributes)
        }
        if request.layout.numbers || !request.pro {
            let label = (request.layout.numbers ? String(page) : "ShotPDF") as NSString
            let width = label.size(withAttributes: attributes).width
            label.draw(at: CGPoint(x: content.maxX - width, y: y), withAttributes: attributes)
        }
    }

    static func defaultName(date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd"
        return L.t("file.prefix") + "_" + format.string(from: date) + ".pdf"
    }

    static func name(_ input: String) -> String? {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        var stem = input.components(separatedBy: unsafe).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if stem.lowercased().hasSuffix(".pdf") { stem.removeLast(4) }
        stem = String(stem.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.utf8.count > 220 { stem.removeLast() }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? nil : stem + ".pdf"
    }
}
