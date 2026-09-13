import Foundation

// Android payloads are inspected and stored, never evaluated or loaded as code.
enum SecretGramPluginFormat: String, Codable {
    case python, dex, archive
}

struct SecretGramPluginRecord: Codable, Equatable {
    let id: UUID
    let filename: String
    let name: String
    let version: String
    let format: SecretGramPluginFormat
    let importedAt: Date
}

enum SecretGramPluginError: Error {
    case unsupportedExtension, invalidContent, tooLarge, storageFull
}

final class SecretGramPluginStore {
    static let maximumBytes = 10 * 1024 * 1024
    let root: URL

    init(root: URL) { self.root = root }

    static func inspect(data: Data, filename: String) throws -> SecretGramPluginRecord {
        guard data.count <= maximumBytes else { throw SecretGramPluginError.tooLarge }
        let ext = (filename as NSString).pathExtension.lowercased()
        guard ext == "plugin" || ext == "dex" else { throw SecretGramPluginError.unsupportedExtension }
        let format: SecretGramPluginFormat
        var name = (filename as NSString).deletingPathExtension
        var version = ""
        if ext == "dex" {
            // Identify a DEX container, not a promise of VM compatibility or validity.
            let magic = Array(data.prefix(8))
            guard data.count >= 112, magic.count == 8,
                  Array(magic.prefix(4)) == [100, 101, 120, 10], magic[7] == 0,
                  magic[4...6].allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
                throw SecretGramPluginError.invalidContent
            }
            format = .dex
        } else if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            format = .archive
        } else {
            guard let source = String(data: data, encoding: .utf8), !source.contains("\0"),
                  let pluginId = metadata("id", source: source), !pluginId.isEmpty,
                  source.contains("BasePlugin") else { throw SecretGramPluginError.invalidContent }
            format = .python
            name = metadata("name", source: source) ?? name
            version = metadata("version", source: source) ?? ""
        }
        return SecretGramPluginRecord(id: UUID(), filename: String(filename.prefix(255)),
                                      name: String(name.prefix(200)), version: String(version.prefix(80)),
                                      format: format, importedAt: Date())
    }

    private static func metadata(_ key: String, source: String) -> String? {
        // Only literal, single-line constants; no Python expressions are evaluated.
        let pattern = "(?m)^__" + key + "__[ \\t]*=[ \\t]*([\"'])([^\\r\\n]*?)\\1[ \\t]*(?:#.*)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 2), in: source) else { return nil }
        return String(source[range])
    }

    func records() throws -> [SecretGramPluginRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { directory -> SecretGramPluginRecord? in
                guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
                let data = try Data(contentsOf: directory.appendingPathComponent("record.json"))
                let record = try JSONDecoder().decode(SecretGramPluginRecord.self, from: data)
                guard record.id == id else { throw SecretGramPluginError.invalidContent }
                return record
            }.sorted { $0.importedAt > $1.importedAt }
    }

    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SecretGramPluginError.invalidContent }
        guard (values.fileSize ?? 0) <= Self.maximumBytes else { throw SecretGramPluginError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        let record = try Self.inspect(data: data, filename: url.lastPathComponent)
        let existing = try records()
        guard existing.count < 50 else { throw SecretGramPluginError.storageFull }
        let fm = FileManager.default
        let used = try existing.reduce(0) { total, item in
            let attrs = try fm.attributesOfItem(atPath: root.appendingPathComponent(item.id.uuidString).appendingPathComponent("payload").path)
            return total + ((attrs[.size] as? NSNumber)?.intValue ?? 0)
        }
        guard used + data.count <= 100 * 1024 * 1024 else { throw SecretGramPluginError.storageFull }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".import-" + record.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: staging.appendingPathComponent("payload"), options: .atomic)
        try JSONEncoder().encode(record).write(to: staging.appendingPathComponent("record.json"), options: .atomic)
        try fm.moveItem(at: staging, to: root.appendingPathComponent(record.id.uuidString, isDirectory: true))
    }

    func remove(_ id: UUID) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
