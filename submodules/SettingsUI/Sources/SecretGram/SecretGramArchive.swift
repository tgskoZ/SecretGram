import Foundation

public enum SecretGramArchiveEventKindV1: String, Codable, CaseIterable {
    case profileSnapshot
    case presence
    case gift
    case edit
    case delete
    case deletedReply
}

public struct SecretGramArchiveManifestV1: Codable, Equatable {
    public var schemaVersion: Int = 1
    public let createdTimestamp: Int64
    public let sourceBuild: Int

    public init(createdTimestamp: Int64, sourceBuild: Int) {
        self.createdTimestamp = createdTimestamp
        self.sourceBuild = sourceBuild
    }
}

public struct SecretGramArchiveEventIdentityV1: Hashable, Comparable {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let messageId: Int32
    public let eventTimestamp: Int64
    public let kind: SecretGramArchiveEventKindV1

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.eventTimestamp != rhs.eventTimestamp { return lhs.eventTimestamp < rhs.eventTimestamp }
        if lhs.accountPeerId != rhs.accountPeerId { return lhs.accountPeerId < rhs.accountPeerId }
        if lhs.peerId != rhs.peerId { return lhs.peerId < rhs.peerId }
        if lhs.messageId != rhs.messageId { return lhs.messageId < rhs.messageId }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

public struct SecretGramArchiveEventV1: Codable, Equatable {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let messageId: Int32
    public let eventTimestamp: Int64
    public let kind: SecretGramArchiveEventKindV1
    public let payload: [String: String]

    public var identity: SecretGramArchiveEventIdentityV1 {
        return SecretGramArchiveEventIdentityV1(
            accountPeerId: self.accountPeerId,
            peerId: self.peerId,
            messageId: self.messageId,
            eventTimestamp: self.eventTimestamp,
            kind: self.kind
        )
    }
}

public struct SecretGramArchiveV1: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var manifest: SecretGramArchiveManifestV1
    public var events: [SecretGramArchiveEventV1]

    public init(manifest: SecretGramArchiveManifestV1, events: [SecretGramArchiveEventV1]) {
        self.manifest = manifest
        self.events = events
    }
}

public enum SecretGramArchiveError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case eventLimitExceeded(Int)
}

public enum SecretGramArchiveCodec {
    public static let maximumEventCount = 100_000

    public static func encode(_ archive: SecretGramArchiveV1) throws -> Data {
        try self.validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = JSONEncoder.OutputFormatting.sortedKeys
        return try encoder.encode(archive)
    }

    public static func decode(_ data: Data) throws -> SecretGramArchiveV1 {
        let archive = try JSONDecoder().decode(SecretGramArchiveV1.self, from: data)
        try self.validate(archive)
        return archive
    }

    public static func merged(
        current: SecretGramArchiveV1,
        imported: SecretGramArchiveV1
    ) throws -> SecretGramArchiveV1 {
        try self.validate(current)
        try self.validate(imported)
        var values: [SecretGramArchiveEventIdentityV1: SecretGramArchiveEventV1] = [:]
        for event in current.events { values[event.identity] = event }
        for event in imported.events { values[event.identity] = event }
        let events = values.values.sorted { $0.identity < $1.identity }
        guard events.count <= self.maximumEventCount else {
            throw SecretGramArchiveError.eventLimitExceeded(events.count)
        }
        return SecretGramArchiveV1(manifest: imported.manifest, events: events)
    }

    private static func validate(_ archive: SecretGramArchiveV1) throws {
        guard archive.schemaVersion == 1, archive.manifest.schemaVersion == 1 else {
            throw SecretGramArchiveError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        guard archive.events.count <= self.maximumEventCount else {
            throw SecretGramArchiveError.eventLimitExceeded(archive.events.count)
        }
    }
}
