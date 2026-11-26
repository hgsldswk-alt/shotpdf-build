import Foundation

struct Entitlement: Codable, Equatable {
    static let trialDuration: TimeInterval = 30 * 86_400
    var firstOpen: Date
    var proStartedAt: Date?
    var purchasedPro = false

    var trialStart: Date { proStartedAt ?? firstOpen }
    var trialEnd: Date { trialStart.addingTimeInterval(Self.trialDuration) }

    func hasPro(at now: Date, free: Bool = Launch.freePeriod) -> Bool {
        free || purchasedPro || (now >= trialStart && now < trialEnd)
    }

    func remainingDays(at now: Date) -> Int {
        max(0, Int(ceil(trialEnd.timeIntervalSince(now) / 86_400)))
    }
}
