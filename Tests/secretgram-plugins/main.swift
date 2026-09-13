import Foundation

func expectFailure(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected failure") } catch {}
}

let source = """
__id__ = "example"
__name__ = 'Example'
__version__ = "1.2"
from base_plugin import BasePlugin
class Example(BasePlugin):
    pass
"""
let bytes = Data(source.utf8)
let record = try SecretGramPluginStore.inspect(data: bytes, filename: "example.PLUGIN")
assert(record.name == "Example" && record.version == "1.2" && record.format == .python)
expectFailure { _ = try SecretGramPluginStore.inspect(data: bytes, filename: "example.exe") }
expectFailure { _ = try SecretGramPluginStore.inspect(data: Data("garbage".utf8), filename: "bad.plugin") }
expectFailure { _ = try SecretGramPluginStore.inspect(data: Data(repeating: 0, count: SecretGramPluginStore.maximumBytes + 1), filename: "huge.plugin") }
expectFailure { _ = try SecretGramPluginStore.inspect(data: Data("dex\n035\0".utf8), filename: "truncated.dex") }
var dex = Data("dex\n035\0".utf8)
dex.append(Data(repeating: 0, count: 104))
let dexRecord = try SecretGramPluginStore.inspect(data: dex, filename: "module.dex")
assert(dexRecord.format == .dex)
// Metadata expressions must never be evaluated.
let expression = source.replacingOccurrences(of: "'Example'", with: "__import__('os').system('false')")
let inert = try SecretGramPluginStore.inspect(data: Data(expression.utf8), filename: "inert.plugin")
assert(inert.name == "inert")

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporary) }
let input = temporary.appendingPathComponent("example.plugin")
try bytes.write(to: input)
let store = SecretGramPluginStore(root: temporary.appendingPathComponent("store"))
try store.importFile(input)
try store.importFile(input)
let stored = try store.records()
assert(stored.count == 2 && stored[0].id != stored[1].id)
let reopened = SecretGramPluginStore(root: store.root)
let reopenedRecords = try reopened.records()
assert(reopenedRecords == stored)
try reopened.remove(stored[0].id)
let remaining = try reopened.records()
assert(remaining.count == 1)
assert(FileManager.default.fileExists(atPath: input.path))
expectFailure { try store.importFile(temporary) }
print("SecretGram plugin inspection and storage tests passed")
