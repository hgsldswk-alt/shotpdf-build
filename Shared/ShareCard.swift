import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct CardContent {
    static let tags = "#スクショ整理 #PDF"
    let images: Int
    let pages: Int
    var milestone = false
    var storeURL = Launch.storeURL

    var qrText: String { storeURL?.absoluteString ?? "https://apps.apple.com/app/id__APP_STORE_ID__" }

    static func qr(_ text: String) -> UIImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(text.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let quietZone = enlarged.extent.insetBy(dx: -32, dy: -32)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: quietZone)
        let padded = enlarged.composited(over: white)
        guard let image = CIContext().createCGImage(padded, from: quietZone) else { return nil }
        return UIImage(cgImage: image)
    }

    @MainActor func write() throws -> URL {
        let card = ShareArtwork(content: self, poster: true).frame(width: 360, height: 450)
            .dynamicTypeSize(.medium)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else { throw ShotError.storage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotShare-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(milestone ? "ShotPDF-50.png" : "ShotPDF.png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct ShareArtwork: View {
    let content: CardContent
    var poster = false

    var body: some View {
        VStack(alignment: .leading, spacing: poster ? 18 : 10) {
            Image(systemName: content.milestone ? "rosette" : "doc.on.doc")
                .font(.system(size: poster ? 52 : 29, weight: .medium))
                .foregroundStyle(Theme.accent).accessibilityHidden(true)
            if content.milestone {
                Text(L.t("share.milestone")).font(.system(poster ? .largeTitle : .title2, design: .rounded, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 4) {
                metric(content.images, suffix: L.t("share.images"))
                metric(content.pages, suffix: L.t("share.pages"), prefix: "→ A4 ")
            }
            Spacer(minLength: 7)
            HStack(alignment: .bottom) {
                Text(CardContent.tags).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    if let code = CardContent.qr(content.qrText) {
                        Image(uiImage: code).interpolation(.none).resizable().scaledToFit()
                            .frame(width: poster ? 83 : 52, height: poster ? 83 : 52)
                            .padding(poster ? 12 : 8).background(.white)
                            .accessibilityLabel(L.t("share.qr"))
                    }
                    if content.storeURL == nil { Text(L.t("share.sampleQR")).font(.caption2).foregroundStyle(Theme.muted) }
                }
            }
        }
        .foregroundStyle(Theme.ink).padding(poster ? 28 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [.white, Theme.blueWash], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .top) {
            Rectangle().fill(LinearGradient(colors: [Theme.accent, Theme.green], startPoint: .leading, endPoint: .trailing))
                .frame(height: poster ? 7 : 4)
        }
        .overlay { RoundedRectangle(cornerRadius: poster ? 0 : 18).strokeBorder(Theme.line).allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: poster ? 0 : 18))
        .shadow(color: Theme.ink.opacity(poster ? 0 : 0.07), radius: 12, x: 0, y: 4)
    }

    private func metric(_ count: Int, suffix: String, prefix: String = "") -> some View {
        let large = Font.system(size: poster ? 39 : 28, weight: .bold, design: .rounded)
        let small = Font.system(size: poster ? 24 : 17, weight: .semibold)
        return (Text(prefix).font(small) + Text(count, format: .number).font(large) + Text(suffix).font(small))
            .fixedSize(horizontal: false, vertical: true)
    }
}
