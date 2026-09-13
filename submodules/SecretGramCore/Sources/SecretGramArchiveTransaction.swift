import Foundation

public enum SecretGramImportEventDisposition: Equatable {
    case new
    case duplicate
    case conflict
}

public struct SecretGramImportAccountPreview: Equatable {
    public let accountPeerId: Int64
    public let newCount: Int
    public let duplicateCount: Int
    public let conflictCount: Int
    public let uncompressedBytes: Int64
}

public struct SecretGramImportPreview: Equatable {
    public let accounts: [SecretGramImportAccountPreview]
    public let settingsWillChange: Bool
}

public protocol SecretGramSettingsSnapshotStore: AnyObject {
    func snapshot(accountPeerId: Int64) throws -> SecretGramSettingsSnapshot
    func replace(_ snapshot: SecretGramSettingsSnapshot) throws
}

public protocol SecretGramRetentionConfigurationStore: AnyObject {
    func configuration(accountPeerId: Int64) throws -> SecretGramRetentionConfiguration
    func replace(_ configuration: SecretGramRetentionConfiguration) throws
}

public enum SecretGramArchiveTransaction {
    public static func classify(
        incoming: SecretGramCanonicalEvent,
        existingById: [SecretGramEventId: SecretGramCanonicalEvent]
    ) -> SecretGramImportEventDisposition {
        guard let existing = existingById[incoming.eventId] else { return .new }
        return existing == incoming ? .duplicate : .conflict
    }

    public static func apply(
        selectedAccountPeerIds: Set<Int64>,
        availableAccountPeerIds: Set<Int64>,
        incomingEvents: [Int64: [SecretGramCanonicalEvent]],
        incomingSettings: [Int64: SecretGramSettingsSnapshot],
        confirmSettingsChanges: Bool,
        eventStore: SecretGramEventStore,
        settingsStore: SecretGramSettingsSnapshotStore,
        incomingRetention: [Int64: SecretGramRetentionConfiguration] = [:],
        retentionStore: SecretGramRetentionConfigurationStore? = nil
    ) throws {
        guard selectedAccountPeerIds.isSubset(of: availableAccountPeerIds) else {
            let missing = selectedAccountPeerIds.subtracting(availableAccountPeerIds).sorted().first!
            throw SecretGramArchiveValidationError.unavailableAccount(missing)
        }
        if !incomingSettings.keys.filter(selectedAccountPeerIds.contains).isEmpty && !confirmSettingsChanges {
            throw SecretGramArchiveValidationError.settingsConfirmationRequired
        }

        var eventRollback: [Int64: [SecretGramCanonicalEvent]] = [:]
        var settingsRollback: [Int64: SecretGramSettingsSnapshot] = [:]
        var retentionRollback: [Int64: SecretGramRetentionConfiguration] = [:]
        do {
            for accountPeerId in selectedAccountPeerIds.sorted() {
                let existing = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
                eventRollback[accountPeerId] = existing
                settingsRollback[accountPeerId] = try settingsStore.snapshot(accountPeerId: accountPeerId)
                if incomingRetention[accountPeerId] != nil, let retentionStore {
                    retentionRollback[accountPeerId] = try retentionStore.configuration(accountPeerId: accountPeerId)
                }
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.eventId, $0) })
                var merged = existing
                var conflicts = 0
                for event in incomingEvents[accountPeerId] ?? [] {
                    guard event.accountPeerId == accountPeerId else {
                        throw SecretGramArchiveValidationError.unavailableAccount(event.accountPeerId)
                    }
                    switch classify(incoming: event, existingById: existingById) {
                    case .new:
                        merged.append(event)
                    case .duplicate:
                        break
                    case .conflict:
                        conflicts += 1
                    }
                }
                guard conflicts == 0 else {
                    throw SecretGramArchiveValidationError.conflictsPresent(conflicts)
                }
                try eventStore.replaceAtomically(accountPeerId: accountPeerId, events: merged)
                if let settings = incomingSettings[accountPeerId] {
                    guard settings.accountPeerId == accountPeerId else {
                        throw SecretGramArchiveValidationError.unavailableAccount(settings.accountPeerId)
                    }
                    try settingsStore.replace(settings)
                }
                if let retention = incomingRetention[accountPeerId], let retentionStore {
                    guard retention.accountPeerId == accountPeerId else {
                        throw SecretGramArchiveValidationError.unavailableAccount(retention.accountPeerId)
                    }
                    try retentionStore.replace(retention)
                }
            }
        } catch {
            // Rollback is best-effort for every already touched exact account;
            // original error remains the reported failure.
            for accountPeerId in eventRollback.keys.sorted() {
                if let events = eventRollback[accountPeerId] {
                    try? eventStore.replaceAtomically(accountPeerId: accountPeerId, events: events)
                }
                if let settings = settingsRollback[accountPeerId] {
                    try? settingsStore.replace(settings)
                }
                if let retention = retentionRollback[accountPeerId], let retentionStore {
                    try? retentionStore.replace(retention)
                }
            }
            throw error
        }
    }
}
