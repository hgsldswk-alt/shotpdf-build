import CoreImage
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import ShotPDF

final class CoreTests: XCTestCase {
    private func workspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = Workspace(root: root)
        try workspace.prepare()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return workspace
    }

    private func shot(_ index: Int, second: Double? = nil, width: Int = 720, height: Int = 960) -> Shot {
        Shot(selected: index, taken: second.map(Date.init(timeIntervalSince1970:)), width: width, height: height)
    }

    func testStableDateSortingAndManualAppend() {
        var draft = Draft(shots: [shot(3, second: 50), shot(4), shot(1, second: 50), shot(0, second: 12), shot(2)])
        draft.sort(.ascending)
        XCTAssertEqual(draft.shots.map(\.selected), [0, 1, 3, 2, 4])
        draft.sort(.descending)
        XCTAssertEqual(draft.shots.map(\.selected), [1, 3, 0, 2, 4])
        draft.sort(.selection)
        XCTAssertEqual(draft.shots.map(\.selected), [0, 1, 2, 3, 4])
        draft.move(draft.shots[3].id, to: 0)
        draft.shots.append(shot(5, second: 1))
        draft.sort(draft.order)
        XCTAssertEqual(draft.order, .manual)
        XCTAssertEqual(draft.shots.map(\.selected), [3, 0, 1, 2, 4, 5])
    }

    func testAllGridsAndWholeImageFitting() throws {
        let shots = (0..<13).map { shot($0) }
        for (grid, count) in zip(Grid.allCases, [13, 7, 4, 3]) {
            let layout = Layout(grid: grid, margin: 16, numbers: true, date: true)
            let plan = try PagePlan.make(shots: shots, layout: layout, pro: true, cuts: [:]) { _ in
                XCTFail("Ordinary screenshots are not analyzed for breaks")
                return RowInk(costs: [])
            }
            XCTAssertEqual(plan.pages.count, count)
            XCTAssertEqual(plan.pages.flatMap { $0.map(\.shot) }, shots)
            XCTAssertEqual(plan.content.minX, 16 * PagePlan.pointsPerMM, accuracy: 0.001)
            for item in plan.pages.flatMap({ $0 }) {
                XCTAssertEqual(item.target.width / item.target.height, 0.75, accuracy: 0.001)
                XCTAssertTrue(plan.content.insetBy(dx: -0.001, dy: -0.001).contains(item.target))
            }
        }
    }

    func testLongCutAvoidsTextAndOverlapPreservesEveryRow() {
        var costs = [Double](repeating: 0, count: 1_100)
        for line in 473...513 { costs[line] = 0.2 }
        let ink = RowInk(costs: costs)
        let clean = LongPlan.make(height: 1_100, capacity: 500, overlap: 14, ink: ink, overrides: [:])
        XCTAssertEqual(clean.cuts.first?.position, 472)
        XCTAssertEqual(clean.cuts.first?.overlap, 0)
        let dense = RowInk(costs: [Double](repeating: 0.2, count: 1_100))
        let fallback = LongPlan.make(height: 1_100, capacity: 500, overlap: 14, ink: dense, overrides: [0: 420])
        XCTAssertEqual(fallback.cuts.first?.position, 420)
        XCTAssertEqual(fallback.cuts.first?.overlap, 14)
        XCTAssertEqual(fallback.slices.first?.start, 0)
        XCTAssertEqual(fallback.slices.last?.end, 1_100)
        for (first, second) in zip(fallback.slices, fallback.slices.dropFirst()) {
            XCTAssertEqual(first.end - second.start, 14)
            XCTAssertLessThanOrEqual(first.end - first.start, 500)
        }
    }

    func testRasterHeuristicRejectsDarkTextLikeRowsNearTarget() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 144, height: 1_100), format: format)
        let sample = try XCTUnwrap(renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 144, height: 1_100))
            UIColor.black.setFill()
            for x in stride(from: 22, through: 120, by: 8) {
                context.fill(CGRect(x: x, y: 480, width: 3, height: 37))
            }
        }.cgImage)
        let ink = try RowInk(image: sample)
        XCTAssertTrue(ink.clear(at: 460, sourceHeight: 1_100))
        XCTAssertFalse(ink.clear(at: 500, sourceHeight: 1_100))
        let plan = LongPlan.make(height: 1_100, capacity: 500, overlap: 14, ink: ink, overrides: [:])
        XCTAssertLessThan(try XCTUnwrap(plan.cuts.first).position, 480)
    }

    func testMixedLongAndShortOrder() throws {
        let images = [shot(0), shot(1, height: 1_880), shot(2), shot(3)]
        let plan = try PagePlan.make(shots: images, layout: Layout(), pro: true, cuts: [:]) { input in
            RowInk(costs: [Double](repeating: 0, count: input.height))
        }
        XCTAssertEqual(plan.pages.map { $0.map(\.shot.selected) }, [[0], [1], [1], [2, 3]])
        XCTAssertEqual(plan.splits.first?.firstPage, 2)
        XCTAssertEqual(plan.splits.first?.cuts.first?.nextPage, 3)
        XCTAssertEqual(plan.pages[1][0].target.width, plan.pages[2][0].target.width)
        XCTAssertEqual(plan.pages[1][0].target.minY, plan.pages[2][0].target.minY)
    }

    func testFreeLimitRequiresExplicitChoiceAndKeepsDraft() throws {
        let draft = Draft(shots: (0..<11).map { shot($0) })
        XCTAssertThrowsError(try draft.exportShots(pro: false, firstTen: false)) {
            XCTAssertEqual($0 as? ShotError, .freeLimit)
        }
        XCTAssertEqual(try draft.exportShots(pro: false, firstTen: true).count, 10)
        XCTAssertEqual(try draft.exportShots(pro: true, firstTen: false).count, 11)
        XCTAssertEqual(draft.shots.count, 11)
        let atLimit = Draft(shots: Array(draft.shots.prefix(10)))
        XCTAssertEqual(try atLimit.exportShots(pro: false, firstTen: false).count, 10)
        let configured = Layout(grid: .six, margin: 25, numbers: true, date: true)
        XCTAssertEqual(configured.effective(pro: false),
                       Layout(grid: .six, margin: 10, numbers: false, date: false, splitLong: false))
    }

    func testTrialIsExactlyThirtyDays() {
        let start = Date(timeIntervalSince1970: 1_800_000)
        var entitlement = Entitlement(firstOpen: start.addingTimeInterval(-100), proStartedAt: start)
        let end = start.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(entitlement.hasPro(at: start.addingTimeInterval(-1), free: false))
        XCTAssertTrue(entitlement.hasPro(at: start, free: false))
        XCTAssertTrue(entitlement.hasPro(at: end.addingTimeInterval(-0.01), free: false))
        XCTAssertFalse(entitlement.hasPro(at: end, free: false))
        XCTAssertTrue(entitlement.hasPro(at: end, free: true))
        entitlement.purchasedPro = true
        XCTAssertTrue(entitlement.hasPro(at: end, free: false))
    }

    @MainActor func testModelReadsClockAfterLoadingFirstOpen() throws {
        let before = Date(timeIntervalSince1970: 1_800_000)
        let firstOpen = before.addingTimeInterval(1)
        var time = before
        let model = AppModel(workspace: try workspace(), clock: { time }, loadEntitlement: {
            time = firstOpen.addingTimeInterval(0.001)
            return Entitlement(firstOpen: firstOpen)
        })
        XCTAssertEqual(model.now, time)
        XCTAssertTrue(model.hasPro)
        time = firstOpen.addingTimeInterval(30 * 86_400)
        model.refreshClock()
        XCTAssertFalse(model.hasPro)
    }

    func testDraftAndMissingFilesRecover() throws {
        let workspace = try workspace()
        let picked = try SeedShots.make(1)
        defer { try? FileManager.default.removeItem(at: picked) }
        let saved = try ImageFiles.install(picked, for: Shot(selected: 0), workspace: workspace)
        let draft = Draft(shots: [saved], order: .manual, layout: Layout(grid: .four), quality: .compact)
        try workspace.save(draft)
        XCTAssertEqual(try workspace.loadDraft(), draft)
        try FileManager.default.removeItem(at: workspace.source(saved.id))
        XCTAssertEqual(try workspace.loadDraft()?.shots.first?.issue, .unavailable)
        try workspace.save(nil)
        XCTAssertNil(try workspace.loadDraft())
    }

    func testEXIFOrientationAndCaptureDate() throws {
        let workspace = try workspace()
        let url = workspace.root.appendingPathComponent("rotated.jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 30), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = try XCTUnwrap(renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
        }.cgImage)
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:26 09:05:00"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let metadata = try ImageFiles.metadata(url)
        XCTAssertEqual(metadata.width, 30)
        XCTAssertEqual(metadata.height, 60)
        XCTAssertNotNil(metadata.taken)
        let normalized = try ImageFiles.decoded(url, maxEdge: 60)
        XCTAssertEqual(normalized.width, 30)
        XCTAssertEqual(normalized.height, 60)
    }

    @MainActor func testPDFGeometryAndExportReusesPreview() async throws {
        let model = AppModel(workspace: try workspace(), loadEntitlement: { Entitlement(firstOpen: .now) })
        await model.ingest([1, 2, 3, 24].map(ImportSource.example), mode: .new)
        var layout = model.layout
        layout.numbers = true
        layout.date = true
        XCTAssertTrue(model.updateLayout(layout, applyToDraft: true))
        await model.render(openPreview: true)
        let preview = try XCTUnwrap(model.preview, model.problem ?? "")
        let document = try XCTUnwrap(PDFDocument(url: preview.url))
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertEqual(preview.sourceCount, 4)
        XCTAssertEqual(preview.byteCount, try Data(contentsOf: preview.url).count)
        let first = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(first.bounds(for: .mediaBox).width, 595.28, accuracy: 0.05)
        XCTAssertEqual(first.bounds(for: .mediaBox).height, 841.89, accuracy: 0.05)
        XCTAssertTrue(first.string?.contains("1") == true)
        await model.render(openPreview: false)
        XCTAssertEqual(model.finished?.url, preview.url)
        XCTAssertTrue(model.rename("Receipts.pdf"))
        XCTAssertEqual(model.finished?.url.lastPathComponent, "Receipts.pdf")
        let relaunched = AppModel(workspace: model.workspace, loadEntitlement: { Entitlement(firstOpen: .now) })
        XCTAssertEqual(relaunched.finished?.url.lastPathComponent, "Receipts.pdf")
    }

    func testPresetValidatesVersionBytesKeysAndMargin() throws {
        let layout = Layout(grid: .four, margin: 25, numbers: true, date: true)
        let code = try Preset.encode(layout)
        XCTAssertEqual(try Preset.decode(" \n" + code), layout)
        XCTAssertThrowsError(try Preset.decode(code.replacingOccurrences(of: "A4P1:", with: "A4P2:")))
        XCTAssertThrowsError(try Preset.decode(String(repeating: "あ", count: 172)))
        XCTAssertThrowsError(try Preset.decode(Preset.encode(Layout(margin: 26))))
        let extra = Data(#"{"grid":2,"date":true,"numbers":true,"margin":10,"splitLong":true,"private":"image"}"#.utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try Preset.decode("A4P1:" + extra))
    }

    func testReviewNeedsThreeDifferentDaysAndOneAttemptPerVersion() {
        var review = ReviewProgress()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let start = Date(timeIntervalSince1970: 1_800_000)
        for offset in [0, 1, 2, 86_400] {
            review.recordExport(at: start.addingTimeInterval(Double(offset)), calendar: calendar)
        }
        XCTAssertFalse(review.eligible(version: "1.0"))
        review.recordExport(at: start.addingTimeInterval(172_800), calendar: calendar)
        XCTAssertTrue(review.eligible(version: "1.0"))
        review.markRequested(version: "1.0")
        XCTAssertFalse(review.eligible(version: "1.0"))
        XCTAssertTrue(review.eligible(version: "1.1"))
    }

    @MainActor func testShareCardDimensionsAndQRDestination() throws {
        let store = try XCTUnwrap(URL(string: "https://apps.apple.com/app/id12345"))
        let card = CardContent(images: 50, pages: 27, milestone: true, storeURL: store)
        let url = try card.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let rendered = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertEqual(rendered.width, 1080)
        XCTAssertEqual(rendered.height, 1350)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let qr = try XCTUnwrap(CardContent.qr(card.qrText)?.cgImage)
        let contents = detector.features(in: CIImage(cgImage: qr)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(contents, [store.absoluteString])
        XCTAssertEqual(CardContent.tags, "#スクショ整理 #PDF")
    }
}
