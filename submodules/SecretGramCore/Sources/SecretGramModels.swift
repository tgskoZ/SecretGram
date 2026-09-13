import Foundation

public struct SecretGramEventId: RawRepresentable, Codable, Hashable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: SecretGramEventId, rhs: SecretGramEventId) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public static func random() -> SecretGramEventId {
        return SecretGramEventId(rawValue: UUID().uuidString.lowercased())
    }

    public static func migrated(
        accountPeerId: Int64,
        chatPeerId: Int64,
        messageNamespace: Int32?,
        messageId: Int32?,
        kind: SecretGramEventKind,
        observedAtMs: Int64,
        discriminator: String
    ) -> SecretGramEventId {
        let structuralValue = [
            String(accountPeerId),
            String(chatPeerId),
            messageNamespace.map(String.init) ?? "-",
            messageId.map(String.init) ?? "-",
            kind.rawValue,
            String(observedAtMs),
            discriminator,
        ].joined(separator: ":")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in structuralValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return SecretGramEventId(rawValue: "m1-" + String(hash, radix: 16))
    }
}

public enum SecretGramEventKind: String, Codable, CaseIterable, Hashable {
    case deletedMessage
    case editedMessage
    case deletedReply
    case recoveredMedia
    case profileSnapshot
    case presence
    case gift
    case personalChannel
}

public struct SecretGramEventPayload: Codable, Equatable {
    public var text: String?
    public var previousText: String?
    public var mediaKind: String?
    public var mediaRelativePath: String?
    public var mediaByteCount: Int64?
    public var metadata: [String: String]

    public init(
        text: String? = nil,
        previousText: String? = nil,
        mediaKind: String? = nil,
        mediaRelativePath: String? = nil,
        mediaByteCount: Int64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.text = text
        self.previousText = previousText
        self.mediaKind = mediaKind
        self.mediaRelativePath = mediaRelativePath
        self.mediaByteCount = mediaByteCount
        self.metadata = metadata
    }
}

public struct SecretGramCanonicalEvent: Codable, Equatable {
    public let schemaVersion: Int
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let eventId: SecretGramEventId
    public let sequence: Int64
    public let kind: SecretGramEventKind
    public let senderPeerId: Int64?
    public let messageNamespace: Int32?
    public let messageId: Int32?
    public let observedAtMs: Int64
    public let payload: SecretGramEventPayload

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        eventId: SecretGramEventId,
        sequence: Int64,
        kind: SecretGramEventKind,
        senderPeerId: Int64?,
        messageNamespace: Int32?,
        messageId: Int32?,
        observedAtMs: Int64,
        payload: SecretGramEventPayload
    ) {
        self.schemaVersion = 1
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.eventId = eventId
        self.sequence = sequence
        self.kind = kind
        self.senderPeerId = senderPeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.observedAtMs = observedAtMs
        self.payload = payload
    }
}

public enum SecretGramCoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case duplicateEvent(SecretGramEventId)
    case conflictingEvent(SecretGramEventId)
    case invalidRelativePath(String)
    case accountScopeMismatch(expected: Int64, actual: Int64)
    case incompleteRead(expected: Int, actual: Int)
    case invalidIndexRange
    case indexNotReady(Int64)
}
