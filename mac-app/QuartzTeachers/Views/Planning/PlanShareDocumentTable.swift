import AppKit
import SwiftUI

/// One of the two tables before a share of unit plans (#833): a standard
/// `NSTableView` (columns with the system's sort indicator, alternating
/// rows, type-to-select, multiple selection) that drags its selected rows to
/// the other table and takes the other table's rows dropped on it.
///
/// An `NSTableView` rather than SwiftUI's `Table` because dragging SEVERAL
/// selected rows and dropping on the table rather than on a row are the
/// table's own data-source calls here, and `PlanShareTablesTests` drives
/// them against a real table and pasteboard; with `Table` they could be
/// proved only by driving the window (unitPlanning.share.rejected).
struct PlanShareDocumentTable: NSViewRepresentable {

    // MARK: - Stored properties

    /// The type a dragged row carries: its place in the plan.
    static let pasteboardType: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType("ca.russellgordon.plantoir.plan-document")

    let model: PlanShareTablesModel
    let table: PlanShareTable

    /// What the table shows, read in the parent's body so a change to the
    /// model redraws it.
    let rows: [PlanShareDocument]
    let selected: Set<String>
    let header: String

    // MARK: - Functions

    func makeCoordinator() -> Coordinator {
        return Coordinator(model: model, table: table)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView: NSTableView = PlanShareDocumentTable.makeTable(coordinator: context.coordinator)
        let scroll: NSScrollView = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        context.coordinator.tableView = tableView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.show(rows: rows, selected: selected, header: header)
    }

    /// The table itself, with its columns, its sort and its drag types.
    static func makeTable(coordinator: Coordinator) -> NSTableView {
        let tableView: NSTableView = NSTableView()
        let columns: [(PlanShareTablesModel.Column, String, CGFloat)] = [
            (.name, PlanShareTableWording.columnName, 190),
            (.unit, PlanShareTableWording.columnUnit, 90),
            (.folder, PlanShareTableWording.columnFolder, 80),
            (.kind, PlanShareTableWording.columnKind, 60),
            (.note, PlanShareTableWording.columnNote, 150),
        ]
        for (column, title, width) in columns {
            let tableColumn: NSTableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = title
            tableColumn.width = width
            tableColumn.minWidth = 44
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            tableView.addTableColumn(tableColumn)
        }
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsTypeSelect = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        tableView.registerForDraggedTypes([pasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.sortDescriptors = descriptors(for: coordinator.model.sort[coordinator.table] ?? [])
        let menu: NSMenu = NSMenu()
        menu.delegate = coordinator
        tableView.menu = menu
        tableView.setAccessibilityIdentifier(coordinator.table == .shared ? "planShareTableShared" : "planShareTableNotShared")
        return tableView
    }

    static func descriptors(for keys: [PlanShareTablesModel.SortKey]) -> [NSSortDescriptor] {
        var result: [NSSortDescriptor] = []
        for key in keys {
            result.append(NSSortDescriptor(key: key.column.rawValue, ascending: key.ascending))
        }
        return result
    }

    static func sortKeys(from descriptors: [NSSortDescriptor]) -> [PlanShareTablesModel.SortKey] {
        var result: [PlanShareTablesModel.SortKey] = []
        for descriptor in descriptors {
            if let key = descriptor.key, let column = PlanShareTablesModel.Column(rawValue: key) {
                result.append(PlanShareTablesModel.SortKey(column: column, ascending: descriptor.ascending))
            }
        }
        return result
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        // MARK: - Stored properties

        let model: PlanShareTablesModel
        let table: PlanShareTable
        weak var tableView: NSTableView?
        var rows: [PlanShareDocument] = []

        /// True while the table is being redrawn from the model, so the
        /// selection it sets is not written back as the teacher's.
        private var isShowing: Bool = false

        // MARK: - Initializer

        init(model: PlanShareTablesModel, table: PlanShareTable) {
            self.model = model
            self.table = table
        }

        // MARK: - Functions

        func show(rows: [PlanShareDocument], selected: Set<String>, header: String) {
            guard let tableView = tableView else {
                self.rows = rows
                return
            }
            isShowing = true
            self.rows = rows
            tableView.reloadData()
            var indexes: IndexSet = IndexSet()
            for (index, row) in rows.enumerated() where selected.contains(row.place) {
                indexes.insert(index)
            }
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            tableView.setAccessibilityLabel(header)
            isShowing = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return rows.count
        }

        func text(for document: PlanShareDocument, column: String) -> String {
            switch PlanShareTablesModel.Column(rawValue: column) {
            case .name:
                return document.name
            case .unit:
                return document.unitShown
            case .folder:
                return document.folder
            case .kind:
                return document.kind
            case .note:
                return model.note(for: document)
            case .none:
                return ""
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, row >= 0, row < rows.count else {
                return nil
            }
            let document: PlanShareDocument = rows[row]
            let identifier: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("cell." + column.identifier.rawValue)
            let cell: NSTableCellView = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? Coordinator.makeCell(identifier: identifier)
            let words: String = text(for: document, column: column.identifier.rawValue)
            cell.textField?.stringValue = words
            cell.textField?.toolTip = column.identifier.rawValue == PlanShareTablesModel.Column.name.rawValue ? document.place : (words.isEmpty ? nil : words)
            let warns: Bool = column.identifier.rawValue == PlanShareTablesModel.Column.note.rawValue
                && document.warns(in: table, isProtected: model.isProtected)
            // A symbol beside the words, never colour alone (#833).
            cell.imageView?.image = warns
                ? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: PlanShareTableWording.noteOpenKey)
                : nil
            cell.imageView?.isHidden = !warns
            return cell
        }

        /// A cell of words; the Note column's has room for the warning
        /// symbol before them.
        static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell: NSTableCellView = NSTableCellView()
            cell.identifier = identifier
            let field: NSTextField = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(field)
            cell.textField = field
            var constraints: [NSLayoutConstraint] = [
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ]
            if identifier.rawValue == "cell." + PlanShareTablesModel.Column.note.rawValue {
                let image: NSImageView = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.contentTintColor = .systemOrange
                image.isHidden = true
                cell.addSubview(image)
                cell.imageView = image
                constraints.append(image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
                constraints.append(image.centerYAnchor.constraint(equalTo: cell.centerYAnchor))
                constraints.append(image.widthAnchor.constraint(equalToConstant: 14))
                constraints.append(field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 2))
            } else {
                constraints.append(field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
            }
            NSLayoutConstraint.activate(constraints)
            return cell
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            guard row >= 0, row < rows.count else {
                return nil
            }
            return rows[row].name
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isShowing, let tableView = tableView else {
                return
            }
            var chosen: Set<String> = []
            for index in tableView.selectedRowIndexes where index < rows.count {
                chosen.insert(rows[index].place)
            }
            model.selection[table] = chosen
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            model.sort[table] = PlanShareDocumentTable.sortKeys(from: tableView.sortDescriptors)
        }

        // MARK: - Functions: drag and drop

        /// A row that can be moved is dragged as its place; one that cannot
        /// is not dragged at all.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row >= 0, row < rows.count, rows[row].movable else {
                return nil
            }
            let item: NSPasteboardItem = NSPasteboardItem()
            item.setString(rows[row].place, forType: PlanShareDocumentTable.pasteboardType)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard Coordinator.isFromAnotherTable(info.draggingSource, than: tableView) else {
                return []
            }
            // The whole table is the target: a document has no place in
            // the other table's order but the one its sort gives it.
            tableView.setDropRow(-1, dropOperation: .on)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard Coordinator.isFromAnotherTable(info.draggingSource, than: tableView) else {
                return false
            }
            return drop(Coordinator.places(on: info.draggingPasteboard))
        }

        static func isFromAnotherTable(_ source: Any?, than tableView: NSTableView) -> Bool {
            guard let other = source as? NSTableView else {
                return false
            }
            return other !== tableView
        }

        /// The places a drag carries.
        static func places(on pasteboard: NSPasteboard) -> Set<String> {
            var found: Set<String> = []
            for item in pasteboard.pasteboardItems ?? [] {
                if let place = item.string(forType: PlanShareDocumentTable.pasteboardType) {
                    found.insert(place)
                }
            }
            return found
        }

        /// Moves dropped rows into this table and says so to VoiceOver.
        @discardableResult
        func drop(_ places: Set<String>) -> Bool {
            let moved: Int = model.move(places, to: table)
            if moved > 0 {
                PlanShareAnnouncer.say(model.lastAnnouncement)
            }
            return moved > 0
        }

        // MARK: - Functions: the context menu

        /// One item, "Don't Share" in Shared and "Share" in Not shared, for
        /// the clicked row, with the rest of the selection when it is part
        /// of it.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView = tableView else {
                return
            }
            let clicked: Int = tableView.clickedRow
            guard clicked >= 0, clicked < rows.count, rows[clicked].movable else {
                return
            }
            let title: String = table == .shared ? PlanShareTableWording.moveToNotShared : PlanShareTableWording.moveToShared
            // The key the sheet answers for the same move, shown on the item
            // so it can be found (#457: shortcuts are discovered on menus).
            let arrow: Int = table == .shared ? NSRightArrowFunctionKey : NSLeftArrowFunctionKey
            let key: String = String(Character(UnicodeScalar(UInt16(arrow)) ?? " "))
            let item: NSMenuItem = NSMenuItem(title: title, action: #selector(moveFromTheMenu(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = .command
            item.target = self
            menu.addItem(item)
        }

        @objc func moveFromTheMenu(_ sender: Any?) {
            guard let tableView = tableView else {
                return
            }
            let clicked: Int = tableView.clickedRow
            guard clicked >= 0, clicked < rows.count else {
                return
            }
            var chosen: Set<String> = [rows[clicked].place]
            if tableView.selectedRowIndexes.contains(clicked) {
                for index in tableView.selectedRowIndexes where index < rows.count {
                    chosen.insert(rows[index].place)
                }
            }
            let destination: PlanShareTable = table == .shared ? .notShared : .shared
            if model.move(chosen, to: destination) > 0 {
                PlanShareAnnouncer.say(model.lastAnnouncement)
            }
        }
    }
}

/// Says a move to VoiceOver (#833: a drag is not reachable from the
/// keyboard or VoiceOver, so every way of moving says what it did).
enum PlanShareAnnouncer {

    // MARK: - Functions

    static func say(_ sentence: String) {
        if sentence.isEmpty {
            return
        }
        let element: Any = NSApp.keyWindow ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: sentence,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// The sheet's search field: the system's own (a magnifying glass and a
/// clear button), filtering both tables as the teacher types. While its
/// window has the keys, ⌘F puts the cursor in it and ⌘→ and ⌘← move the
/// selected rows (`onMove`, true toward Not shared): a watcher on that
/// window's key presses, removed with the field, because a shortcut is never
/// hung on a button in a view (#457) and these are the sheet's own keys.
struct PlanShareSearchField: NSViewRepresentable {

    // MARK: - Stored properties

    @Binding var text: String
    let onMove: (Bool) -> Void

    // MARK: - Functions

    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field: NSSearchField = NSSearchField()
        field.placeholderString = PlanShareTableWording.searchPrompt
        field.setAccessibilityLabel(PlanShareTableWording.searchPrompt)
        field.setAccessibilityIdentifier("planShareSearch")
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        context.coordinator.field = field
        context.coordinator.watchTheKeys()
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onMove = onMove
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {

        // MARK: - Stored properties

        var text: Binding<String>
        var onMove: (Bool) -> Void
        weak var field: NSSearchField?
        private var watcher: Any?

        // MARK: - Initializer

        init(text: Binding<String>, onMove: @escaping (Bool) -> Void) {
            self.text = text
            self.onMove = onMove
        }

        // MARK: - Functions

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                text.wrappedValue = field.stringValue
            }
        }

        func watchTheKeys() {
            watcher = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] (event: NSEvent) -> NSEvent? in
                guard let self = self else {
                    return event
                }
                return self.handle(event)
            }
        }

        func stopWatching() {
            if let watcher = watcher {
                NSEvent.removeMonitor(watcher)
            }
            watcher = nil
        }

        /// Whether the cursor is in this search field.
        func isTyping(in window: NSWindow) -> Bool {
            guard let field = field, let editor = window.firstResponder as? NSText else {
                return false
            }
            return editor.delegate === field
        }

        /// ⌘F, ⌘→ and ⌘← in this sheet's window, and Return while the
        /// cursor is in the search field, which stays there rather than
        /// press Cancel, the sheet's default button (review L5: the search
        /// is made as the teacher types, so Return has nothing left to do).
        /// Every other key passes.
        func handle(_ event: NSEvent) -> NSEvent? {
            guard let field = field, let window = field.window, event.window === window else {
                return event
            }
            let modifiers: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isReturn: Bool = event.keyCode == 36 || event.keyCode == 76
            if isReturn && !modifiers.contains(.command) && isTyping(in: window) {
                return nil
            }
            guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else {
                return event
            }
            let characters: String = event.charactersIgnoringModifiers ?? ""
            if characters.lowercased() == "f" && !modifiers.contains(.shift) {
                window.makeFirstResponder(field)
                return nil
            }
            // In the search field ⌘→ and ⌘← keep their meaning there: the
            // start and the end of the line.
            if window.firstResponder is NSText {
                return event
            }
            if let scalar = characters.unicodeScalars.first {
                if scalar.value == UInt32(NSRightArrowFunctionKey) {
                    onMove(true)
                    return nil
                }
                if scalar.value == UInt32(NSLeftArrowFunctionKey) {
                    onMove(false)
                    return nil
                }
            }
            return event
        }
    }
}
