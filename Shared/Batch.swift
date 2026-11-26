import Foundation

enum ShotError: String, LocalizedError {
    case unreadable, storage, noSpace, tooLarge, missing, noImages, freeLimit, pdf, preset, store, noPurchase

    var errorDescription: String? { L.t("error." + rawValue) }

    static func disk(_ error: Error) -> ShotError {
        if let issue = error as? ShotError { return issue }
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteOutOfSpaceError { return .noSpace }
        if let cause = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
           cause.domain == NSPOSIXErrorDomain && cause.code == Int(ENOSPC) { return .noSpace }
        return .storage
    }
}

enum Grid: Int, Codable, Sendable, CaseIterable {
    case one = 1, two = 2, four = 4, six = 6
    var columns: Int { self == .one ? 1 : 2 }
    var rows: Int { rawValue / columns }
}

enum PDFQuality: String, Codable, Sendable, CaseIterable {
    case clear, compact
    var title: String { L.t("quality." + rawValue) }
}

struct Layout: Codable, Equatable, Sendable {
    var grid: Grid = .two
    var margin: Int = 10
    var numbers = false
    var date = false
    var splitLong = true

    var isValid: Bool { (5...25).contains(margin) }
    var usesPro: Bool { margin != 10 || numbers || date || splitLong }

    func effective(pro: Bool) -> Self {
        pro ? self : Self(grid: grid, margin: 10, numbers: false, date: false, splitLong: false)
    }
}

enum Preset {
    static let prefix = "A4P1:"

    static func encode(_ layout: Layout) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return prefix + (try encoder.encode(layout)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws -> Layout {
        guard text.utf8.count <= 512 else { throw ShotError.preset }
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(prefix) else { throw ShotError.preset }
        let body = code.dropFirst(prefix.count)
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard !body.isEmpty, body.count % 4 != 1, body.allSatisfy(alphabet.contains) else { throw ShotError.preset }
        let base64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64 + String(repeating: "=", count: (4 - body.count % 4) % 4)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["grid", "margin", "numbers", "date", "splitLong"],
              let layout = try? JSONDecoder().decode(Layout.self, from: data),
              layout.isValid else { throw ShotError.preset }
        return layout
    }
}

enum ShotOrder: String, CaseIterable, Codable, Sendable {
    case ascending, descending, selection, manual
    var title: String { L.t("sort." + rawValue) }
}

enum ImportIssue: String, Codable, Sendable {
    case unavailable, unreadable, storage, noSpace
    var title: String { L.t("import." + rawValue) }
}

struct Shot: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var selected: Int
    var taken: Date?
    var width = 0
    var height = 0
    var issue: ImportIssue?

    var available: Bool { issue == nil && width > 0 && height > 0 }
}

struct Draft: Codable, Equatable, Sendable {
    var shots: [Shot] = []
    var order: ShotOrder = .ascending
    var layout = Layout()
    var quality: PDFQuality = .clear
    var cuts: [UUID: [Int: Int]] = [:]

    mutating func sort(_ order: ShotOrder) {
        self.order = order
        guard order != .manual else { return }
        shots.sort { lhs, rhs in
            guard order != .selection, lhs.taken != rhs.taken else { return lhs.selected < rhs.selected }
            guard let a = lhs.taken else { return false }
            guard let b = rhs.taken else { return true }
            return order == .ascending ? a < b : a > b
        }
    }

    mutating func move(_ id: UUID, to index: Int) {
        guard let old = shots.firstIndex(where: { $0.id == id }), shots.indices.contains(index), old != index else { return }
        shots.insert(shots.remove(at: old), at: index)
        order = .manual
    }

    func exportShots(pro: Bool, firstTen: Bool) throws -> [Shot] {
        guard !shots.isEmpty else { throw ShotError.noImages }
        if !pro && shots.count > 10 && !firstTen { throw ShotError.freeLimit }
        let selection = !pro && firstTen ? Array(shots.prefix(10)) : shots
        guard selection.allSatisfy(\.available) else { throw ShotError.missing }
        return selection
    }
}

struct ReviewProgress: Codable {
    private var count = 0
    private var days: Set<String> = []
    private(set) var requestedVersions: Set<String> = []
    var earnedMilestone = false

    mutating func recordExport(at date: Date, calendar: Calendar = .current) {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        days.insert("\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)")
        if count < Int.max { count += 1 }
    }

    func eligible(version: String) -> Bool { count >= 3 && days.count >= 3 && !requestedVersions.contains(version) }

    mutating func markRequested(version: String) { requestedVersions.insert(version) }
}
