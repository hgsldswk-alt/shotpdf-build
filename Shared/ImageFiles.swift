import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Workspace: Sendable {
    let root: URL

    var sources: URL { root.appendingPathComponent("Sources", isDirectory: true) }
    var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    var output: URL { root.appendingPathComponent("Output", isDirectory: true) }
    var draftURL: URL { root.appendingPathComponent("draft.json") }
    var progressURL: URL { root.appendingPathComponent("progress.json") }

    func prepare() throws {
        for directory in [root, sources, thumbnails, output] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var privateRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateRoot.setResourceValues(values)
    }

    func source(_ id: UUID) -> URL { sources.appendingPathComponent(id.uuidString) }
    func thumb(_ id: UUID) -> URL { thumbnails.appendingPathComponent(id.uuidString + ".jpg") }

    func loadDraft() throws -> Draft? {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        var draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: draftURL))
        guard draft.layout.isValid else { throw ShotError.storage }
        for index in draft.shots.indices where draft.shots[index].available {
            if !FileManager.default.fileExists(atPath: source(draft.shots[index].id).path) {
                draft.shots[index].issue = .unavailable
            }
        }
        return draft
    }

    func save(_ value: Draft?) throws {
        let files = FileManager.default
        if let value {
            try JSONEncoder().encode(value).write(to: draftURL, options: .atomic)
        } else if files.fileExists(atPath: draftURL.path) {
            try files.removeItem(at: draftURL)
        }
    }

    func pruneImages(keeping ids: Set<UUID>) {
        for directory in [sources, thumbnails] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !ids.contains(id) else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func checkSpace(_ minimum: Int64) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        if let value = attributes[.systemFreeSize] as? NSNumber, value.int64Value < minimum {
            throw ShotError.noSpace
        }
    }
}

enum ImageFiles {
    static let sourceByteLimit = 256 * 1024 * 1024
    private static let pixelBudget: Double = 20_000_000
    private static let largeThumbnailLock = NSLock()

    static func metadata(_ url: URL) throws -> (width: Int, height: Int, taken: Date?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, width > 0,
              let height = props[kCGImagePropertyPixelHeight] as? Int, height > 0 else { throw ShotError.unreadable }
        guard max(width, height) <= 200_000,
              Double(width) * Double(height) <= 48_000_000 else { throw ShotError.tooLarge }
        let rotated = (5...8).contains(props[kCGImagePropertyOrientation] as? Int ?? 1)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let dates = [
            (exif[kCGImagePropertyExifDateTimeOriginal] as? String, exif["OffsetTimeOriginal" as CFString] as? String),
            (exif[kCGImagePropertyExifDateTimeDigitized] as? String, exif["OffsetTimeDigitized" as CFString] as? String),
            (tiff[kCGImagePropertyTIFFDateTime] as? String, exif["OffsetTime" as CFString] as? String)
        ]
        let taken = dates.lazy.compactMap { date($0.0, offset: $0.1) }.first
        return (rotated ? height : width, rotated ? width : height, taken)
    }

    private static func date(_ text: String?, offset: String?) -> Date? {
        guard let text, text.count == 19 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
        return formatter.date(from: text + (offset ?? ""))
    }

    static func decoded(_ url: URL, maxEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxEdge),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ShotError.unreadable }
        return image
    }

    static func renderImage(_ url: URL, width: Int, height: Int, targetWidth: Int) throws -> CGImage {
        let budgetScale = sqrt(pixelBudget / (Double(width) * Double(height)))
        let scale = min(1, min(budgetScale, Double(targetWidth) / Double(width)))
        let edge = min(32_768, max(1, Int((Double(max(width, height)) * scale).rounded())))
        return try decoded(url, maxEdge: edge)
    }

    static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let buffer = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(buffer as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ShotError.pdf
        }
        CGImageDestinationAddImage(writer, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1)
        ] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw ShotError.pdf }
        return buffer as Data
    }

    static func install(_ temporary: URL, for shot: Shot, workspace: Workspace, photoDate: Date? = nil) throws -> Shot {
        let byteCount = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteCount <= sourceByteLimit else { throw ShotError.tooLarge }
        try workspace.checkSpace(Int64(byteCount) + 2 * 1024 * 1024)
        let info = try metadata(temporary)
        let thumbnail: CGImage
        if Int64(info.width) * Int64(info.height) > 12_000_000 {
            largeThumbnailLock.lock()
            defer { largeThumbnailLock.unlock() }
            thumbnail = try decoded(temporary, maxEdge: 280)
        } else {
            thumbnail = try decoded(temporary, maxEdge: 280)
        }
        try jpeg(thumbnail, quality: 0.84).write(to: workspace.thumb(shot.id), options: .atomic)
        let destination = workspace.source(shot.id)
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try files.moveItem(at: temporary, to: destination)
        }
        var result = shot
        result.width = info.width
        result.height = info.height
        result.taken = info.taken ?? photoDate
        result.issue = nil
        return result
    }
}
