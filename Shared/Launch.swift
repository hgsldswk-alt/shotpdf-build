import Foundation

enum Launch {
    static let freePeriod = false
    static let proID = "com.hgsldswk.shotpdf.pro"

    #if DEBUG
    static let arguments = ProcessInfo.processInfo.arguments
    static let isTesting = arguments.contains("-ui-testing") || arguments.contains("-seed")
    static let hostedTests = ProcessInfo.processInfo.environment["SHOTPDF_HOSTED_TESTS"] == "1"
    #else
    static let arguments: [String] = []
    static let isTesting = false
    static let hostedTests = false
    #endif

    static var storeURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}
