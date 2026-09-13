import Foundation

public enum SecretGramHistoryDuration: String, Codable, CaseIterable {
    case disabled
    case days7
    case days30
    case days90
    case forever

    public var durationMs: Int64? {
        switch self {
        case .disabled:
            return 0
        case .days7:
            return 7 * 86_400_000
        case .days30:
            return 30 * 86_400_000
        case .days90:
            return 90 * 86_400_000
        case .forever:
            return nil
        }
    }
}

public enum SecretGramMediaByteLimit: String, Codable, CaseIterable {
    case disabled
    case megabytes250
    case megabytes500
    case gigabytes1
    case gigabytes2
    case gigabytes5
    case unlimited

    public var byteCount: Int64? {
        switch self {
        case .disabled:
            return 0
        case .megabytes250:
            return 250 * 1_048_576
        case .megabytes500:
            return 500 * 1_048_576
        case .gigabytes1:
            return 1_073_741_824
        case .gigabytes2:
            return 2 * 1_073_741_824
        case .gigabytes5:
            return 5 * 1_073_741_824
        case .unlimited:
            return nil
        }
    }
}

public struct SecretGramRetentionPolicy: Codable, Equatable {
    public var historyDuration: SecretGramHistoryDuration
    public var mediaByteLimit: SecretGramMediaByteLimit
    public var archiveSecretChats: Bool

    public init(
        historyDuration: SecretGramHistoryDuration = .days30,
        mediaByteLimit: SecretGramMediaByteLimit = .gigabytes1,
        archiveSecretChats: Bool = false
    ) {
        self.historyDuration = historyDuration
        self.mediaByteLimit = mediaByteLimit
        self.archiveSecretChats = archiveSecretChats
    }
}

public struct SecretGramChatRetentionOverride: Codable, Equatable {
    public let chatPeerId: Int64
    public var captureEnabled: Bool?
    public var historyDuration: SecretGramHistoryDuration?
    public var mediaByteLimit: SecretGramMediaByteLimit?
    public var archiveSecretChats: Bool?

    public init(
        chatPeerId: Int64,
        captureEnabled: Bool? = nil,
        historyDuration: SecretGramHistoryDuration? = nil,
        mediaByteLimit: SecretGramMediaByteLimit? = nil,
        archiveSecretChats: Bool? = nil
    ) {
        self.chatPeerId = chatPeerId
        self.captureEnabled = captureEnabled
        self.historyDuration = historyDuration
        self.mediaByteLimit = mediaByteLimit
        self.archiveSecretChats = archiveSecretChats
    }
}

public struct SecretGramRetentionConfiguration: Codable, Equatable {
    public let schemaVersion: Int
    public let accountPeerId: Int64
    public var accountPolicy: SecretGramRetentionPolicy
    public var chatOverrides: [SecretGramChatRetentionOverride]

    public init(
        accountPeerId: Int64,
        accountPolicy: SecretGramRetentionPolicy = SecretGramRetentionPolicy(
            historyDuration: .days30,
            mediaByteLimit: .gigabytes1,
            archiveSecretChats: false
        ),
        chatOverrides: [SecretGramChatRetentionOverride] = []
    ) {
        self.schemaVersion = 1
        self.accountPeerId = accountPeerId
        self.accountPolicy = accountPolicy
        self.chatOverrides = chatOverrides
    }

    public func effectivePolicy(chatPeerId: Int64) -> (Bool, SecretGramRetentionPolicy) {
        guard let override = self.chatOverrides.first(where: { $0.chatPeerId == chatPeerId }) else {
            return (true, self.accountPolicy)
        }
        return (
            override.captureEnabled ?? true,
            SecretGramRetentionPolicy(
                historyDuration: override.historyDuration ?? self.accountPolicy.historyDuration,
                mediaByteLimit: override.mediaByteLimit ?? self.accountPolicy.mediaByteLimit,
                archiveSecretChats: override.archiveSecretChats ?? self.accountPolicy.archiveSecretChats
            )
        )
    }
}

public final class SecretGramRetentionStore {
    private let rootURL: URL
    private let lock = NSLock()

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func load(accountPeerId: Int64) throws -> SecretGramRetentionConfiguration {
        self.lock.lock()
        defer { self.lock.unlock() }
        let url = self.url(accountPeerId: accountPeerId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SecretGramRetentionConfiguration(accountPeerId: accountPeerId)
        }
        let value = try JSONDecoder().decode(
            SecretGramRetentionConfiguration.self,
            from: Data(contentsOf: url)
        )
        guard value.schemaVersion == 1 else {
            throw SecretGramCoreError.unsupportedSchemaVersion(value.schemaVersion)
        }
        return value
    }

    public func save(_ value: SecretGramRetentionConfiguration) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        let url = self.url(accountPeerId: value.accountPeerId)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func url(accountPeerId: Int64) -> URL {
        return self.rootURL.appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(String(accountPeerId), isDirectory: true)
            .appendingPathComponent("retention.json", isDirectory: false)
    }
}

/// Small synchronous bridge used by TelegramCore at the exact delete/edit
/// transaction boundary. Values are keyed by the real Telegram account peer
/// id and chat peer id; there is deliberately no "current account" fallback.
public enum SecretGramRetentionRuntime {
    private struct Snapshot {
        let configuration: SecretGramRetentionConfiguration
        let chatOverridesByPeerId: [Int64: SecretGramChatRetentionOverride]

        init(configuration: SecretGramRetentionConfiguration) {
            self.configuration = configuration
            var chatOverridesByPeerId: [Int64: SecretGramChatRetentionOverride] = [:]
            for override in configuration.chatOverrides {
                chatOverridesByPeerId[override.chatPeerId] = override
            }
            self.chatOverridesByPeerId = chatOverridesByPeerId
        }

        func effectivePolicy(chatPeerId: Int64) -> (Bool, SecretGramRetentionPolicy) {
            guard let override = self.chatOverridesByPeerId[chatPeerId] else {
                return (true, self.configuration.accountPolicy)
            }
            return (
                override.captureEnabled ?? true,
                SecretGramRetentionPolicy(
                    historyDuration: override.historyDuration ?? self.configuration.accountPolicy.historyDuration,
                    mediaByteLimit: override.mediaByteLimit ?? self.configuration.accountPolicy.mediaByteLimit,
                    archiveSecretChats: override.archiveSecretChats ?? self.configuration.accountPolicy.archiveSecretChats
                )
            )
        }
    }

    private static let lock = NSLock()
    private static var snapshots: [Int64: Snapshot] = [:]

    public static func save(
        _ configuration: SecretGramRetentionConfiguration,
        userDefaults: UserDefaults = .standard
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        self.lock.lock()
        userDefaults.set(data, forKey: self.accountKey(configuration.accountPeerId))
        self.snapshots[configuration.accountPeerId] = Snapshot(configuration: configuration)
        self.lock.unlock()
    }

    public static func configuration(
        accountPeerId: Int64,
        userDefaults: UserDefaults = .standard
    ) -> SecretGramRetentionConfiguration {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let snapshot = self.snapshots[accountPeerId] {
            return snapshot.configuration
        }
        let configuration: SecretGramRetentionConfiguration
        guard let data = userDefaults.data(forKey: self.accountKey(accountPeerId)),
              let value = try? JSONDecoder().decode(SecretGramRetentionConfiguration.self, from: data),
              value.accountPeerId == accountPeerId else {
            configuration = SecretGramRetentionConfiguration(accountPeerId: accountPeerId)
            self.snapshots[accountPeerId] = Snapshot(configuration: configuration)
            return configuration
        }
        configuration = value
        self.snapshots[accountPeerId] = Snapshot(configuration: configuration)
        return configuration
    }

    public static func shouldCapture(
        accountPeerId: Int64,
        chatPeerId: Int64,
        isSecretChat: Bool,
        legacyToggleKey: String,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        self.lock.lock()
        let cachedSnapshot = self.snapshots[accountPeerId]
        self.lock.unlock()
        let snapshot: Snapshot
        if let cachedSnapshot {
            snapshot = cachedSnapshot
        } else {
            let configuration = self.configuration(
                accountPeerId: accountPeerId,
                userDefaults: userDefaults
            )
            self.lock.lock()
            snapshot = self.snapshots[accountPeerId] ?? Snapshot(configuration: configuration)
            self.lock.unlock()
        }
        let (captureEnabled, policy) = snapshot.effectivePolicy(chatPeerId: chatPeerId)
        guard SecretGramRetentionEngine.shouldCapture(
            captureEnabled: captureEnabled,
            policy: policy,
            isSecretChat: isSecretChat
        ) else {
            return false
        }
        let key = self.settingKey(
            accountPeerId: accountPeerId,
            legacyToggleKey: legacyToggleKey
        )
        if let scoped = userDefaults.object(forKey: key) as? Bool {
            return scoped
        }
        // One-time compatibility migration is immediately written under the
        // concrete account id. Subsequent accounts and imports never share it.
        let migrated = (userDefaults.object(forKey: legacyToggleKey) as? Bool) ?? true
        userDefaults.set(migrated, forKey: key)
        return migrated
    }

    private static func accountKey(_ accountPeerId: Int64) -> String {
        return "secretgram.retention.account.\(accountPeerId)"
    }

    private static func settingKey(
        accountPeerId: Int64,
        legacyToggleKey: String
    ) -> String {
        return "secretgram.account.\(accountPeerId).setting.\(legacyToggleKey)"
    }
}

public struct SecretGramCleanupPlan: Equatable {
    public let retainedEvents: [SecretGramCanonicalEvent]
    public let expiredEventIds: [SecretGramEventId]
    public let mediaEventIdsToRemove: [SecretGramEventId]
    public let mediaBytesToRemove: Int64
}

public enum SecretGramRetentionEngine {
    public static func shouldCapture(
        captureEnabled: Bool,
        policy: SecretGramRetentionPolicy,
        isSecretChat: Bool
    ) -> Bool {
        guard captureEnabled, policy.historyDuration != .disabled else { return false }
        if isSecretChat && !policy.archiveSecretChats { return false }
        return true
    }

    public static func cleanupPlan(
        events: [SecretGramCanonicalEvent],
        policy: SecretGramRetentionPolicy,
        nowMs: Int64
    ) -> SecretGramCleanupPlan {
        let retainedEvents: [SecretGramCanonicalEvent]
        let expired: [SecretGramCanonicalEvent]
        if let durationMs = policy.historyDuration.durationMs {
            let cutoff = nowMs - durationMs
            retainedEvents = events.filter { $0.observedAtMs >= cutoff }
            expired = events.filter { $0.observedAtMs < cutoff }
        } else {
            retainedEvents = events
            expired = []
        }

        guard let budget = policy.mediaByteLimit.byteCount else {
            return SecretGramCleanupPlan(
                retainedEvents: retainedEvents,
                expiredEventIds: expired.map(\.eventId),
                mediaEventIdsToRemove: [],
                mediaBytesToRemove: 0
            )
        }
        let media = retainedEvents.compactMap { event -> (SecretGramCanonicalEvent, Int64)? in
            guard event.payload.mediaRelativePath != nil,
                  let count = event.payload.mediaByteCount,
                  count > 0 else {
                return nil
            }
            return (event, count)
        }.sorted { lhs, rhs in
            if lhs.0.observedAtMs != rhs.0.observedAtMs {
                return lhs.0.observedAtMs < rhs.0.observedAtMs
            }
            return lhs.0.eventId < rhs.0.eventId
        }
        var total = media.reduce(Int64(0)) { $0 + $1.1 }
        var removeIds: [SecretGramEventId] = []
        var removeBytes: Int64 = 0
        for (event, count) in media where total > budget {
            removeIds.append(event.eventId)
            removeBytes += count
            total -= count
        }
        return SecretGramCleanupPlan(
            retainedEvents: retainedEvents,
            expiredEventIds: expired.map(\.eventId),
            mediaEventIdsToRemove: removeIds,
            mediaBytesToRemove: removeBytes
        )
    }

    public static func applyCleanup(
        accountPeerId: Int64,
        originalEvents: [SecretGramCanonicalEvent],
        plan: SecretGramCleanupPlan,
        mediaRootURL: URL,
        eventStore: SecretGramEventStore
    ) throws {
        let removeMediaIds = Set(plan.mediaEventIdsToRemove)
        let expiredIds = Set(plan.expiredEventIds)
        for event in originalEvents where removeMediaIds.contains(event.eventId) || expiredIds.contains(event.eventId) {
            guard let relativePath = event.payload.mediaRelativePath,
                  !relativePath.hasPrefix("/"),
                  !relativePath.split(separator: "/").contains("..") else {
                continue
            }
            try? FileManager.default.removeItem(
                at: mediaRootURL.appendingPathComponent(relativePath, isDirectory: false)
            )
        }
        let retained = plan.retainedEvents.map { event -> SecretGramCanonicalEvent in
            guard removeMediaIds.contains(event.eventId) else { return event }
            var payload = event.payload
            payload.mediaRelativePath = nil
            payload.mediaByteCount = nil
            return SecretGramCanonicalEvent(
                accountPeerId: event.accountPeerId,
                chatPeerId: event.chatPeerId,
                eventId: event.eventId,
                sequence: event.sequence,
                kind: event.kind,
                senderPeerId: event.senderPeerId,
                messageNamespace: event.messageNamespace,
                messageId: event.messageId,
                observedAtMs: event.observedAtMs,
                payload: payload
            )
        }
        try eventStore.replaceAtomically(accountPeerId: accountPeerId, events: retained)
    }
}
