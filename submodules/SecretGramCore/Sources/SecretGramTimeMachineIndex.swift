import Foundation

public enum SecretGramTimeMachineFilter: String, Codable, CaseIterable {
    case deleted
    case edited
    case recoveredMedia
}

public struct SecretGramTimeMachineQuery: Equatable {
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let kinds: Set<SecretGramEventKind>
    public let senderPeerId: Int64?
    public let eventIds: Set<SecretGramEventId>?

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        kinds: Set<SecretGramEventKind> = [],
        senderPeerId: Int64? = nil,
        eventIds: Set<SecretGramEventId>? = nil
    ) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.kinds = kinds
        self.senderPeerId = senderPeerId
        self.eventIds = eventIds
    }
}

public struct SecretGramTimeMachineResult: Equatable {
    public let eventId: SecretGramEventId
    public let sequence: Int64
    public let kind: SecretGramEventKind
    public let senderPeerId: Int64?
    public let observedAtMs: Int64
    public let locator: SecretGramCanonicalLocator
}

public final class SecretGramTimeMachineIndex {
    private let records: [SecretGramTimeMachineIndexRecord]

    public init(records: [SecretGramTimeMachineIndexRecord]) {
        // Identity is (accountPeerId, eventId). Equal text is intentionally
        // irrelevant and therefore never used as a deduplication key.
        var identities = Set<String>()
        self.records = records.filter { record in
            identities.insert("\(record.accountPeerId):\(record.eventId.rawValue)").inserted
        }
    }

    public func query(_ query: SecretGramTimeMachineQuery) -> [SecretGramTimeMachineResult] {
        return self.records.lazy.filter { record in
            guard record.accountPeerId == query.accountPeerId,
                  record.chatPeerId == query.chatPeerId else {
                return false
            }
            if !query.kinds.isEmpty && !query.kinds.contains(record.kind) { return false }
            if let senderPeerId = query.senderPeerId, record.senderPeerId != senderPeerId { return false }
            if let eventIds = query.eventIds, !eventIds.contains(record.eventId) { return false }
            return true
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.eventId > rhs.eventId
        }.map { record in
            SecretGramTimeMachineResult(
                eventId: record.eventId,
                sequence: record.sequence,
                kind: record.kind,
                senderPeerId: record.senderPeerId,
                observedAtMs: record.observedAtMs,
                locator: record.locator
            )
        }
    }
}

public struct SecretGramChangesSinceLastOpening: Equatable {
    public let upperSequence: Int64
    public let deletedCount: Int
    public let editedCount: Int
    public let recoveredMediaCount: Int
    public let eventIds: [SecretGramEventId]
}

public final class SecretGramVisitWatermarkStore {
    private let rootURL: URL
    private let lock = NSLock()

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func previousSequence(accountPeerId: Int64, chatPeerId: Int64) -> Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (try? String(
            contentsOf: self.url(accountPeerId: accountPeerId, chatPeerId: chatPeerId),
            encoding: .utf8
        )).flatMap(Int64.init)
    }

    public func snapshotChangesSinceLastOpening(
        accountPeerId: Int64,
        chatPeerId: Int64,
        records: [SecretGramTimeMachineIndexRecord]
    ) throws -> SecretGramChangesSinceLastOpening {
        self.lock.lock()
        defer { self.lock.unlock() }
        let url = self.url(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        let previousValue = (try? String(contentsOf: url, encoding: .utf8)).flatMap(Int64.init)
        let previous = previousValue ?? 0
        let matching = records.filter {
            $0.accountPeerId == accountPeerId &&
            $0.chatPeerId == chatPeerId &&
            $0.sequence > previous
        }
        let upperSequence = matching.map(\.sequence).max() ?? previous
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try String(upperSequence).data(using: .utf8)?.write(to: url, options: .atomic)
        if previousValue == nil {
            return SecretGramChangesSinceLastOpening(
                upperSequence: upperSequence,
                deletedCount: 0,
                editedCount: 0,
                recoveredMediaCount: 0,
                eventIds: []
            )
        }
        return SecretGramChangesSinceLastOpening(
            upperSequence: upperSequence,
            deletedCount: matching.filter { $0.kind == .deletedMessage || $0.kind == .deletedReply }.count,
            editedCount: matching.filter { $0.kind == .editedMessage }.count,
            recoveredMediaCount: matching.filter { $0.kind == .recoveredMedia }.count,
            eventIds: matching.sorted { $0.sequence < $1.sequence }.map(\.eventId)
        )
    }

    public func snapshotChangesSinceLastOpening(
        accountPeerId: Int64,
        chatPeerId: Int64,
        events: [SecretGramCanonicalEvent]
    ) throws -> SecretGramChangesSinceLastOpening {
        let records = events.compactMap { event -> SecretGramTimeMachineIndexRecord? in
            guard event.accountPeerId == accountPeerId, event.chatPeerId == chatPeerId,
                  let locator = try? SecretGramCanonicalLocator(
                    kind: event.kind,
                    relativeFile: "accounts/\(accountPeerId)/events.jsonl",
                    eventId: event.eventId
                  ) else { return nil }
            return SecretGramTimeMachineIndexRecord(
                accountPeerId: event.accountPeerId,
                chatPeerId: event.chatPeerId,
                eventId: event.eventId,
                sequence: event.sequence,
                kind: event.kind,
                senderPeerId: event.senderPeerId,
                observedAtMs: event.observedAtMs,
                locator: locator
            )
        }
        return try self.snapshotChangesSinceLastOpening(
            accountPeerId: accountPeerId,
            chatPeerId: chatPeerId,
            records: records
        )
    }

    private func url(accountPeerId: Int64, chatPeerId: Int64) -> URL {
        // Visit watermarks are local UI state and intentionally live outside
        // Archive v2 account payloads.
        return self.rootURL.appendingPathComponent("visit-watermarks", isDirectory: true)
            .appendingPathComponent(String(accountPeerId), isDirectory: true)
            .appendingPathComponent("\(chatPeerId).txt", isDirectory: false)
    }
}
