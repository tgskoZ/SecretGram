import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import AccountContext
import AlertUI
import LegacyMediaPickerUI

private struct SecretGramPluginsState: Equatable {
    var records: [SecretGramPluginRecord] = []
    var busy = false
    var error = ""
}

private enum SecretGramPluginEntry: ItemListNodeEntry {
    case action(Int32, Int32, String, String)
    case info(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self { case let .action(section, _, _, _), let .info(section, _, _): return section }
    }
    var stableId: Int32 {
        switch self { case let .action(_, id, _, _), let .info(_, id, _): return id }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let action = arguments as! (String) -> Void
        switch self {
        case let .action(_, _, title, key):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic,
                                      alignment: .natural, sectionId: section, style: .blocks, action: { action(key) })
        case let .info(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func secretgramPluginsController(context: AccountContext) -> ViewController {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SecretGram/Plugins/\(context.account.peerId.toInt64())", isDirectory: true)
    let store = SecretGramPluginStore(root: root)
    let queue = DispatchQueue(label: "secretgram.plugin-import", qos: .userInitiated)
    let state = ValuePromise(SecretGramPluginsState(), ignoreRepeated: true)
    var current = SecretGramPluginsState()
    weak var controller: ItemListController?
    func localized(_ ru: String, _ en: String) -> String {
        return context.sharedContext.currentPresentationData.with { $0 }.strings.secretgram.languageCode == "ru" ? ru : en
    }
    func reload(_ operation: @escaping () throws -> Void) {
        guard !current.busy else { return }
        current.busy = true
        current.error = ""
        state.set(current)
        queue.async {
            var records: [SecretGramPluginRecord] = []
            var failure: Error?
            do { try operation(); records = try store.records() } catch { failure = error }
            DispatchQueue.main.async {
                current.busy = false
                if let failure = failure {
                    switch failure {
                    case SecretGramPluginError.tooLarge:
                        current.error = localized("Файл больше 10 МБ.", "File exceeds 10 MB.")
                    case SecretGramPluginError.storageFull:
                        current.error = localized("Хранилище заполнено. Удалите файлы (лимит 50 файлов / 100 МБ).", "Storage full. Remove files (limit: 50 files / 100 MB).")
                    case SecretGramPluginError.unsupportedExtension, SecretGramPluginError.invalidContent:
                        current.error = localized("Не распознан формат .plugin или .dex.", "Unrecognized .plugin or .dex format.")
                    default:
                        current.error = localized("Не удалось прочитать или сохранить файл.", "Unable to read or save the file.")
                    }
                } else { current.records = records }
                state.set(current)
            }
        }
    }
    let action: (String) -> Void = { key in
        guard !current.busy, let controller = controller else { return }
        if key == "import" {
            let presentation = context.sharedContext.currentPresentationData.with { $0 }
            let picker = legacyICloudFilePicker(theme: presentation.theme, mode: .import,
                documentTypes: ["public.data"], completion: { urls in
                    guard let url = urls.first else { return }
                    reload { try store.importFile(url) }
                })
            controller.present(picker, in: .window(.root))
        } else if let id = UUID(uuidString: key), let record = current.records.first(where: { $0.id == id }) {
            let presentation = context.sharedContext.currentPresentationData.with { $0 }
            controller.present(textAlertController(context: context, title: record.name,
                text: localized("Файл сохранён, но не выполняется на iOS. Удалить его?", "Stored, but cannot run on iOS. Delete this file?"),
                actions: [
                    TextAlertAction(type: .genericAction, title: presentation.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: presentation.strings.Common_Delete, action: { reload { try store.remove(id) } })
                ]), in: .window(.root))
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, state.get())
    |> deliverOnMainQueue
    |> map { presentation, value -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentation.strings.secretgram.languageCode == "ru"
        var entries: [SecretGramPluginEntry] = [
            .action(0, 0, value.busy ? (ru ? "Обработка…" : "Processing…") : (ru ? "Импортировать .plugin / .dex" : "Import .plugin / .dex"), "import"),
            .info(0, 1, ru ? "Экспериментальный импорт AyuGram / exteraGram. Файлы сохраняются без запуска. Python-плагинам нужны Android API; DEX нужен Android Runtime. Для работы на iOS требуется перенос кода." : "Experimental AyuGram / exteraGram import. Files are stored without execution. Python plugins require Android APIs; DEX requires Android Runtime. Running on iOS requires porting the code.")
        ]
        if !value.error.isEmpty { entries.append(.info(0, 2, value.error)) }
        if value.records.isEmpty { entries.append(.info(1, 3, ru ? "Нет импортированных файлов." : "No imported files.")) }
        for (index, record) in value.records.enumerated() {
            let base = Int32(10 + index * 2)
            let format: String
            switch record.format { case .python: format = "Python"; case .dex: format = "DEX"; case .archive: format = "ZIP .plugin" }
            entries.append(.action(1, base, record.name, record.id.uuidString))
            entries.append(.info(1, base + 1, "\(record.filename) · \(format) \(record.version) · " + (ru ? "Не выполняется на iOS" : "Cannot run on iOS")))
        }
        return (ItemListControllerState(presentationData: ItemListPresentationData(presentation),
            title: .text(ru ? "Плагины" : "Plugins"), leftNavigationButton: nil, rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentation.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentation), entries: entries,
                              style: .blocks, animateChanges: false), action as Any))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    reload {}
    return result
}
