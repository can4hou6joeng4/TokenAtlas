import Foundation

/// Time window used specifically by the menu-bar status item and floating tab.
///
/// Keeps menu-bar specific options separate from the Usage page while still
/// defaulting to today's calendar window for predictable midnight rollover.
enum MenuBarPeriod: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case currentSession
    case today
    case last7Days
    case last30Days
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentSession: "Current session"
        case .today: StatsPeriod.today.displayName
        case .last7Days: StatsPeriod.last7Days.displayName
        case .last30Days: StatsPeriod.last30Days.displayName
        case .allTime: StatsPeriod.allTime.displayName
        }
    }

    var statsPeriod: StatsPeriod? {
        switch self {
        case .currentSession:
            nil
        case .today:
            .today
        case .last7Days:
            .last7Days
        case .last30Days:
            .last30Days
        case .allTime:
            .allTime
        }
    }
}
