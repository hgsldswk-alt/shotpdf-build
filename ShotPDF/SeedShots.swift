import Foundation
import UIKit

enum SeedShots {
    static func date(_ index: Int) -> Date? {
        if index == 24 { return nil }
        return Date(timeIntervalSince1970: 1_795_683_600 + TimeInterval(index * 193))
    }

    static func make(_ index: Int) throws -> URL {
        let long = index == 24
        let size = CGSize(width: 720, height: long ? 1_880 : 966)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.91, blue: 0.95, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 104))
            let title = long ? L.t("seed.long") : L.t("seed.title" + String(index % 3))
            draw(title, x: 35, y: 28, size: 32, bold: true)
            for row in 0..<(long ? 11 : 5) {
                let y = 130 + row * 145
                let x = row.isMultiple(of: 2) ? 26 : 112
                let width = 575
                let wash = row.isMultiple(of: 2) ? UIColor.white :
                    UIColor(red: 0.87, green: 0.94, blue: 0.91, alpha: 1)
                wash.setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: 108), cornerRadius: 13).fill()
                draw(L.t("seed.line" + String((row + index) % 4)), x: x + 20, y: y + 16, size: 24, bold: row == 0)
                draw(String(format: "%02d / %02d", index, row + 1), x: x + 20, y: y + 61, size: 19, bold: false)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShotImport-" + UUID().uuidString)
        try image.write(to: url)
        return url
    }

    private static func draw(_ string: String, x: Int, y: Int, size: CGFloat, bold: Bool) {
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
            .foregroundColor: UIColor(red: 0.14, green: 0.19, blue: 0.24, alpha: 1)
        ])
    }
}
