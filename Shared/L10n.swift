import Foundation

enum L {
    static func t(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    static func date(_ value: Date) -> String { value.formatted(date: .numeric, time: .omitted) }
    static func timestamp(_ value: Date) -> String { value.formatted(date: .numeric, time: .shortened) }
}
