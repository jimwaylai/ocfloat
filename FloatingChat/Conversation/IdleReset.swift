import Foundation

/// Decides, at Summon only, whether a fresh Conversation should replace the current one.
enum IdleReset {
    static let minutesKey = "idleResetMinutes"
    static let defaultMinutes = 10

    static func threshold(defaults: UserDefaults = .standard) -> TimeInterval {
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        return TimeInterval(max(minutes, 1) * 60)
    }

    static func shouldReset(lastInteraction: Date?, now: Date, threshold: TimeInterval, hasUnreadAnswer: Bool, isAnswering: Bool) -> Bool {
        guard let lastInteraction, !hasUnreadAnswer, !isAnswering else { return false }
        return now.timeIntervalSince(lastInteraction) > threshold
    }
}

/// Persists which Conversation is current, so it survives relaunches.
struct ConversationStore {
    private static let sessionKey = "currentSessionID"
    private static let lastInteractionKey = "lastInteraction"
    let defaults: UserDefaults

    var sessionID: String? {
        get { defaults.string(forKey: Self.sessionKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.sessionKey) }
    }

    var lastInteraction: Date? {
        get { defaults.object(forKey: Self.lastInteractionKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastInteractionKey) }
    }
}
