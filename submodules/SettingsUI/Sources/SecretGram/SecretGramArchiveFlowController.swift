import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import AlertUI
import LegacyMediaPickerUI
import SecretGramCore
import ZipArchive

private let secretgramPortableBooleanKeys: [String] = [
    "secretgram.Profile.Enabled", "secretgram.Profile.ShowIds", "secretgram.Profile.ShowDCs",
    "secretgram.Profile.ShowRegistration", "secretgram.Glass.Enabled",
    "secretgram.ProfileBlur.Avatar", "secretgram.ProfileBlur.Animated",
    "secretgram.ProfileBlur.Tint", "secretgram.ProfileBlur.Reduced",
    "secretgram.GhostMode.ReadMessages", "secretgram.GhostMode.TypingActions",
    "secretgram.GhostMode.HideRecording", "secretgram.GhostMode.HideUploading",
    "secretgram.GhostMode.HideStickerActivity", "secretgram.GhostMode.HideGameActivity",
    "secretgram.GhostMode.HideEmojiActivity", "secretgram.GhostMode.Presence",
    "secretgram.GhostMode.ScheduledSend", "secretgram.Messages.SaveDeleted",
    "secretgram.Messages.ShowDeleted", "secretgram.Messages.SaveEditHistory",
    "secretgram.Messages.ShowEditHistory", "secretgram.Messages.DeletedPortableReplies",
    "secretgram.Messages.PreserveDeletedMedia", "secretgram.Appearance.ShowRamUnderClock",
    "secretgram.Appearance.MessageSeconds", "secretgram.Appearance.HideOwnPhone",
    "secretgram.ProtectedContent.Enabled", "secretgram.ProtectedContent.GalleryShare",
    "secretgram.ProtectedContent.GallerySave", "secretgram.ProtectedContent.GalleryCopy",
    "secretgram.ProtectedContent.ChatSave", "secretgram.ProtectedContent.ChatCopy",
    "secretgram.ProtectedContent.ChatForward", "secretgram.ProtectedContent.AllowScreenshots",
    "secretgram.ProtectedContent.AllowScreenRecording",
    "secretgram.ProtectedContent.OneTimeScreenshots",
    "secretgram.ProtectedContent.OneTimeScreenRecording",
    "secretgram.ProtectedContent.OneTimeSave", "secretgram.Stories.Save",
    "secretgram.Stars.LocalBalance.Enabled",
]

private let secretgramPortableStringKeys = [
    "secretgram.Messages.SendTextStyle",
    "secretgram.Stars.LocalBalance.Amount",
    "secretgram.Stars.LocalBalance.BaseAmount",
]

private let secretgramPortableIntegerKeys = [
    "secretgram.Messages.DeletedMediaCacheLimit",
    "secretgram.Messages.DeletedMediaRetentionDays",
]

private func secretgramCoreRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SecretGram", isDirectory: true)
}

private func secretgramSettingsSnapshot(accountPeerId: Int64) -> SecretGramSettingsSnapshot {
    var toggles: [String: Bool] = [:]
    var strings: [String: String] = [:]
    var integers: [String: Int64] = [:]
    for key in secretgramPortableBooleanKeys {
        let scoped = "secretgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? Bool {
            toggles[key] = value
        } else if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            toggles[key] = value
        }
    }
    for key in secretgramPortableStringKeys {
        let scoped = "secretgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.string(forKey: scoped) {
            strings[key] = value
        } else if let value = UserDefaults.standard.string(forKey: key) {
            strings[key] = value
        }
    }
    for key in secretgramPortableIntegerKeys {
        let scoped = "secretgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? NSNumber {
            integers[key] = value.int64Value
        } else if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            integers[key] = value.int64Value
        }
    }
    return SecretGramSettingsSnapshot(
        accountPeerId: accountPeerId,
        toggles: toggles,
        integerValues: integers,
        stringValues: strings
    )
}

private func secretgramWritePayload<T: Encodable>(
    _ value: T,
    component: SecretGramArchiveComponent,
    relativePath: String,
    rootURL: URL,
    recordCount: Int
) throws -> SecretGramArchivePayloadDescriptor {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let url = rootURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return SecretGramArchivePayloadDescriptor(
        component: component,
        relativePath: relativePath,
        recordCount: recordCount,
        uncompressedBytes: Int64(data.count),
        sha256: SecretGramSHA256.hex(data)
    )
}

private func secretgramPresentArchiveExportError(
    context: AccountContext,
    controller: ViewController,
    text: String
) {
    Queue.mainQueue().async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.secretgram.exportArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func secretgramPresentArchiveExport(
    context: AccountContext,
    controller: ViewController
) {
    let accountPeerId = context.account.peerId.toInt64()

    // Full event snapshotting, JSON encoding and ZIP creation are intentionally
    // kept off the UI thread. Flush the recorder on this worker first so the
    // archive does not race the 250 ms capture buffer and silently miss the
    // newest deleted/edited events.
    Queue.concurrentDefaultQueue().async {
        let workURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("secretgram-export-\(UUID().uuidString)", isDirectory: true)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecretGram-\(accountPeerId).secretgram")
        do {
            SecretGramCaptureRecorder.flushSynchronously()
            try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
            let base = "accounts/\(accountPeerId)"
            let settings = secretgramSettingsSnapshot(accountPeerId: accountPeerId)
            let retention = SecretGramRetentionRuntime.configuration(accountPeerId: accountPeerId)
            let eventStore = SecretGramJSONLEventStore(rootURL: secretgramCoreRootURL())

            // Never convert a canonical-store failure into an apparently valid
            // empty archive. If reading history fails, surface that failure and
            // leave the user's canonical store untouched.
            let events = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
            let descriptors = try [
                secretgramWritePayload(
                    settings,
                    component: .settingsSnapshot,
                    relativePath: "\(base)/settings.json",
                    rootURL: workURL,
                    recordCount: settings.toggles.count + settings.stringValues.count
                ),
                secretgramWritePayload(
                    retention,
                    component: .retentionPolicies,
                    relativePath: "\(base)/retention.json",
                    rootURL: workURL,
                    recordCount: retention.chatOverrides.count + 1
                ),
                secretgramWritePayload(
                    events,
                    component: .canonicalEvents,
                    relativePath: "\(base)/events.json",
                    rootURL: workURL,
                    recordCount: events.count
                ),
            ]
            let manifest = SecretGramArchiveManifestV2(
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
                accounts: [
                    SecretGramArchiveAccountManifest(
                        accountPeerId: accountPeerId,
                        payloads: descriptors
                    )
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(
                to: workURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try? FileManager.default.removeItem(at: outputURL)
            guard SSZipArchive.createZipFile(
                atPath: outputURL.path,
                withContentsOfDirectory: workURL.path
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            Queue.mainQueue().async {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .export,
                    url: outputURL,
                    documentTypes: [],
                    dismissed: {
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    },
                    completion: { _ in
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                )
                controller.present(picker, in: .window(.root), with: nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: workURL)
            try? FileManager.default.removeItem(at: outputURL)
            secretgramPresentArchiveExportError(
                context: context,
                controller: controller,
                text: String(describing: error)
            )
        }
    }
}

private final class SecretGramRuntimeRetentionStore: SecretGramRetentionConfigurationStore {
    func configuration(accountPeerId: Int64) throws -> SecretGramRetentionConfiguration {
        return SecretGramRetentionRuntime.configuration(accountPeerId: accountPeerId)
    }

    func replace(_ configuration: SecretGramRetentionConfiguration) throws {
        try SecretGramRetentionRuntime.save(configuration)
    }
}

private final class SecretGramUserDefaultsSnapshotStore: SecretGramSettingsSnapshotStore {
    func snapshot(accountPeerId: Int64) throws -> SecretGramSettingsSnapshot {
        return secretgramSettingsSnapshot(accountPeerId: accountPeerId)
    }

    func replace(_ snapshot: SecretGramSettingsSnapshot) throws {
        // Replacement is exact so a failed transaction can restore absence as
        // well as values; otherwise newly introduced keys would leak past rollback.
        for key in secretgramPortableBooleanKeys + secretgramPortableStringKeys + secretgramPortableIntegerKeys {
            let scoped = "secretgram.account.\(snapshot.accountPeerId).setting.\(key)"
            UserDefaults.standard.removeObject(forKey: scoped)
        }
        for (key, value) in snapshot.toggles {
            UserDefaults.standard.set(value, forKey: "secretgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.stringValues {
            UserDefaults.standard.set(value, forKey: "secretgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.integerValues {
            UserDefaults.standard.set(value, forKey: "secretgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
    }
}

private func secretgramProjectImportedSettingsToActiveDefaults(_ snapshot: SecretGramSettingsSnapshot) {
    defer {
        SecretGramHotSettings.invalidate()
        SecretGramActivityGhostRuntime.invalidate()
        SecretGramBlockedReactionPolicy.notifySettingsChanged()
        GhostBaseGlassStyle.reloadFromDefaults()
        Queue.mainQueue().async {
            NotificationCenter.default.post(name: Notification.Name("GhostBaseRamOverlayPreferenceChanged"), object: nil)
        }
    }
    let defaults = UserDefaults.standard
    for (key, value) in snapshot.toggles {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.stringValues {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.integerValues {
        defaults.set(value, forKey: key)
    }

    // Archive v2 originally used SecretGram-prefixed portable names while a few
    // Project both spellings for the three synchronous side-effect settings.
    let legacyRuntimeKeys: [String: String] = [
        "secretgram.GhostMode.ScheduledSend": "GhostBase.GhostMode.ScheduledSend",
        "secretgram.ProtectedContent.Enabled": "GhostBase.ProtectedContent.Enabled",
        "secretgram.ProtectedContent.OneTimeSave": "GhostBase.ProtectedContent.OneTimeSave",
    ]
    for (portableKey, legacyKey) in legacyRuntimeKeys {
        if let value = snapshot.toggles[portableKey] {
            defaults.set(value, forKey: legacyKey)
            if legacyKey == "GhostBase.GhostMode.ScheduledSend" {
                (UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? defaults).set(value, forKey: legacyKey)
            }
        }
    }
}

private func secretgramPresentArchiveImportError(
    context: AccountContext,
    controller: ViewController,
    presentationData: PresentationData,
    text: String
) {
    Queue.mainQueue().async {
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.secretgram.importArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func secretgramPresentArchiveImport(
    context: AccountContext,
    controller: ViewController
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()

            // ZIP enumeration/unzip, payload reads and JSON validation are all
            // potentially unbounded file I/O. Never execute them in the file
            // picker/UI callback.
            Queue.concurrentDefaultQueue().async {
                defer {
                    if didAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let workURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("secretgram-import-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: workURL) }

                do {
                    try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                    guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                          entries.count <= SecretGramArchiveV2.maximumPayloadCount + 1 else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    for entry in entries {
                        let normalizedPath = entry.path.hasSuffix("/")
                            ? String(entry.path.dropLast())
                            : entry.path
                        if !normalizedPath.isEmpty {
                            try SecretGramArchiveV2.validateRelativePath(normalizedPath)
                        }
                    }
                    guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }

                    let decoder = JSONDecoder()
                    let manifest = try decoder.decode(
                        SecretGramArchiveManifestV2.self,
                        from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                    )
                    let accountPeerId = context.account.peerId.toInt64()
                    guard let account = manifest.accounts.first(where: { $0.accountPeerId == accountPeerId }) else {
                        throw SecretGramArchiveValidationError.unavailableAccount(accountPeerId)
                    }

                    var payloads: [String: Data] = [:]
                    for descriptor in account.payloads {
                        payloads[descriptor.relativePath] = try Data(
                            contentsOf: workURL.appendingPathComponent(descriptor.relativePath)
                        )
                    }
                    try SecretGramArchiveV2.validateExtractedPayloads(
                        manifest: SecretGramArchiveManifestV2(
                            createdAtMs: manifest.createdAtMs,
                            accounts: [account]
                        ),
                        payloads: payloads
                    )

                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw SecretGramArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(SecretGramSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(SecretGramRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([SecretGramCanonicalEvent].self, from: eventsData)

                    Queue.mainQueue().async {
                        let strings = presentationData.strings.secretgram
                        let alert = textAlertController(
                            context: context,
                            title: strings.importArchive,
                            text: strings.importSettingsConfirmation(accountPeerId),
                            actions: [
                                TextAlertAction(
                                    type: .genericAction,
                                    title: presentationData.strings.Common_Cancel,
                                    action: {}
                                ),
                                TextAlertAction(
                                    type: .defaultAction,
                                    title: strings.importSettings,
                                    action: {
                                        // ArchiveTransaction loads/merges and may atomically
                                        // rewrite the complete canonical account store. Keep
                                        // that transaction and its rollback away from UI.
                                        Queue.concurrentDefaultQueue().async {
                                            do {
                                                let eventStore = SecretGramJSONLEventStore(
                                                    rootURL: secretgramCoreRootURL()
                                                )
                                                let settingsStore = SecretGramUserDefaultsSnapshotStore()
                                                try SecretGramArchiveTransaction.apply(
                                                    selectedAccountPeerIds: [accountPeerId],
                                                    availableAccountPeerIds: [context.account.peerId.toInt64()],
                                                    incomingEvents: [accountPeerId: events],
                                                    incomingSettings: [accountPeerId: settings],
                                                    confirmSettingsChanges: true,
                                                    eventStore: eventStore,
                                                    settingsStore: settingsStore
                                                )
                                                try SecretGramRetentionRuntime.save(retention)
                                                secretgramProjectImportedSettingsToActiveDefaults(settings)
                                                Queue.mainQueue().async {
                                                    secretgramNotifySettingsImported(accountPeerId: accountPeerId)
                                                }
                                            } catch {
                                                secretgramPresentArchiveImportError(
                                                    context: context,
                                                    controller: controller,
                                                    presentationData: presentationData,
                                                    text: String(describing: error)
                                                )
                                            }
                                        }
                                    }
                                ),
                            ]
                        )
                        controller.present(alert, in: .window(.root), with: nil)
                    }
                } catch {
                    secretgramPresentArchiveImportError(
                        context: context,
                        controller: controller,
                        presentationData: presentationData,
                        text: String(describing: error)
                    )
                }
            }
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}

private func secretgramPresentArchiveImportPicker(
    context: AccountContext,
    controller: ViewController,
    availableAccountPeerIds: Set<Int64>
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
            let workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("secretgram-import-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                      entries.count <= SecretGramArchiveV2.maximumPayloadCount + 1 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for entry in entries {
                    let normalizedPath = entry.path.hasSuffix("/")
                        ? String(entry.path.dropLast())
                        : entry.path
                    if !normalizedPath.isEmpty {
                        try SecretGramArchiveV2.validateRelativePath(normalizedPath)
                    }
                }
                guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let decoder = JSONDecoder()
                let manifest = try decoder.decode(
                    SecretGramArchiveManifestV2.self,
                    from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                )
                var payloads: [String: Data] = [:]
                for descriptor in manifest.accounts.flatMap(\.payloads) {
                    payloads[descriptor.relativePath] = try Data(contentsOf: workURL.appendingPathComponent(descriptor.relativePath))
                }
                try SecretGramArchiveV2.validateExtractedPayloads(manifest: manifest, payloads: payloads)

                let matchingAccounts = manifest.accounts.filter { availableAccountPeerIds.contains($0.accountPeerId) }
                guard !matchingAccounts.isEmpty else {
                    throw SecretGramArchiveValidationError.unavailableAccount(manifest.accounts.first?.accountPeerId ?? 0)
                }
                let selectedAccountPeerIds = Set(matchingAccounts.map(\.accountPeerId))
                let disconnected = manifest.accounts.map(\.accountPeerId).filter { !availableAccountPeerIds.contains($0) }.sorted()
                var incomingSettings: [Int64: SecretGramSettingsSnapshot] = [:]
                var incomingRetention: [Int64: SecretGramRetentionConfiguration] = [:]
                var incomingEvents: [Int64: [SecretGramCanonicalEvent]] = [:]
                for account in matchingAccounts {
                    let accountPeerId = account.accountPeerId
                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw SecretGramArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(SecretGramSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(SecretGramRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([SecretGramCanonicalEvent].self, from: eventsData)
                    guard settings.accountPeerId == accountPeerId, retention.accountPeerId == accountPeerId,
                          events.allSatisfy({ $0.accountPeerId == accountPeerId }) else {
                        throw SecretGramArchiveValidationError.unavailableAccount(accountPeerId)
                    }
                    incomingSettings[accountPeerId] = settings
                    incomingRetention[accountPeerId] = retention
                    incomingEvents[accountPeerId] = events
                }
                let strings = presentationData.strings.secretgram
                let connectedLines = selectedAccountPeerIds.sorted().map { "✓ Telegram ID \($0)" }
                let disconnectedSuffix = strings.languageCode == "ru" ? "не подключён — пропущен" : "not connected — skipped"
                let disconnectedLines = disconnected.map { "— Telegram ID \($0) (\(disconnectedSuffix))" }
                let importPreview = (connectedLines + disconnectedLines).joined(separator: "\\n")
                let alert = textAlertController(
                    context: context,
                    title: strings.importArchive,
                    text: importPreview,
                    actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: strings.importSettings, action: {
                            let eventStore = SecretGramJSONLEventStore(rootURL: secretgramCoreRootURL())
                            let settingsStore = SecretGramUserDefaultsSnapshotStore()
                            let retentionStore = SecretGramRuntimeRetentionStore()
                            do {
                                try SecretGramArchiveTransaction.apply(
                                    selectedAccountPeerIds: selectedAccountPeerIds,
                                    availableAccountPeerIds: availableAccountPeerIds,
                                    incomingEvents: incomingEvents,
                                    incomingSettings: incomingSettings,
                                    confirmSettingsChanges: true,
                                    eventStore: eventStore,
                                    settingsStore: settingsStore,
                                    incomingRetention: incomingRetention,
                                    retentionStore: retentionStore
                                )
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: strings.languageCode == "ru" ? "Импорт завершён." : "Import completed.",
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            } catch {
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: String(describing: error),
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            }
                        }),
                    ]
                )
                controller.present(alert, in: .window(.root), with: nil)
            } catch {
                let alert = textAlertController(
                    context: context,
                    title: presentationData.strings.secretgram.importArchive,
                    text: String(describing: error),
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                )
                controller.present(alert, in: .window(.root), with: nil)
            }
            try? FileManager.default.removeItem(at: workURL)
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}
