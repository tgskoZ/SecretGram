import Foundation

public struct SecretGramCanonicalLocator: Codable, Equatable {
    public let kind: SecretGramEventKind
    public let relativeFile: String
    public let eventId: SecretGramEventId

    public init(kind: SecretGramEventKind, relativeFile: String, eventId: SecretGramEventId) throws {
        guard !relativeFile.hasPrefix("/"), !relativeFile.split(separator: "/").contains("..") else {
            throw SecretGramCoreError.invalidRelativePath(relativeFile)
        }
        self.kind = kind
        self.relativeFile = relativeFile
        self.eventId = eventId
    }
}

public struct SecretGramTimeMachineIndexRecord: Codable, Equatable {
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let eventId: SecretGramEventId
    public let sequence: Int64
    public let kind: SecretGramEventKind
    public let senderPeerId: Int64?
    public let observedAtMs: Int64
    public let byteOffset: UInt64
    public let byteLength: UInt64
    public let messageNamespace: Int32?
    public let messageId: Int32?
    public let locator: SecretGramCanonicalLocator

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        eventId: SecretGramEventId,
        sequence: Int64,
        kind: SecretGramEventKind,
        senderPeerId: Int64?,
        observedAtMs: Int64,
        byteOffset: UInt64 = 0,
        byteLength: UInt64 = 0,
        messageNamespace: Int32? = nil,
        messageId: Int32? = nil,
        locator: SecretGramCanonicalLocator
    ) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.eventId = eventId
        self.sequence = sequence
        self.kind = kind
        self.senderPeerId = senderPeerId
        self.observedAtMs = observedAtMs
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.locator = locator
    }
}
