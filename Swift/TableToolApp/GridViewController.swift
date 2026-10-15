import AppKit
import CSVCore

@MainActor
final class GridViewController: NSViewController, @preconcurrency NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    unowned let document: CSVDocument
    let tableView = NSTableView()
    private let encoding = NSPopUpButton()
    private let delimiter = NSTextField(string: ",")
    private let quote = NSPopUpButton()
    private let decimal = NSPopUpButton()
    private let header = NSButton(checkboxWithTitle: "首行为表头", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    var detectionNotice = ""
    private let rowPasteboardType = NSPasteboard.PasteboardType("cc.kneo.TableToolSwift.rows")
    private let dragIdentity = UUID().uuidString
    private var isReloading = false
    private var actionButtons: [NSButton] = []
    init(document: CSVDocument) { self.document = document; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView()
        encoding.addItems(withTitles: CSVEncoding.allCases.map(\.rawValue))
        quote.addItems(withTitles: ["双引号", "单引号", "无引用", "双引号 / 反斜杠"])
        decimal.addItems(withTitles: ["小数点 .", "小数逗号 ,"])
        delimiter.placeholderString = "分隔符（Tab填\\t）"
        delimiter.widthAnchor.constraint(equalToConstant: 90).isActive = true
        delimiter.delegate = self
        for control in [encoding, quote, decimal] { control.target = self; control.action = #selector(formatChanged(_:)) }
        header.target = self; header.action = #selector(formatChanged(_:))
        let format = NSStackView(views: [NSTextField(labelWithString: "输入编码"), encoding,
                                       NSTextField(labelWithString: "分隔符"), delimiter, quote, decimal, header])
        format.orientation = .horizontal
        format.spacing = 8
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.documentView = tableView
        tableView.dataSource = self; tableView.delegate = self
        tableView.allowsMultipleSelection = true; tableView.allowsColumnSelection = true
        tableView.allowsColumnReordering = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.registerForDraggedTypes([rowPasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        NotificationCenter.default.addObserver(self, selector: #selector(columnMoved(_:)), name: NSTableView.columnDidMoveNotification, object: tableView)
        let actions: [(String, Selector)] = [("插入行", #selector(insertRow(_:))), ("删除行", #selector(deleteRows(_:))), ("插入列", #selector(insertColumn(_:))), ("删除列", #selector(deleteColumns(_:))), ("编辑表头", #selector(editHeader(_:)))]
        let buttons = actions.map { NSButton(title: $0.0, target: self, action: $0.1) }
        actionButtons = buttons
        let toolbar = NSStackView(views: buttons)
        toolbar.orientation = .horizontal; toolbar.spacing = 8
        let stack = NSStackView(views: [format, toolbar, scroll, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)])
        status.lineBreakMode = .byTruncatingTail
        reload()
    }
    func reload() {
        guard isViewLoaded else { return }
        isReloading = true
        let rows = tableView.selectedRowIndexes
        let cols = tableView.selectedColumnIndexes
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for (index, id) in document.model.columnOrder.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.uuidString))
            column.title = document.model.title(column: index)
            column.width = 150; column.minWidth = 50
            tableView.addTableColumn(column)
        }
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(rows.filter { $0 < document.model.visibleRowCount }), byExtendingSelection: false)
        tableView.selectColumnIndexes(IndexSet(cols.filter { $0 < document.model.columnOrder.count }), byExtendingSelection: false)
        let config = document.configuration
        encoding.selectItem(withTitle: config.encoding.rawValue)
        delimiter.stringValue = config.delimiter == "\t" ? "\\t" : String(config.delimiter)
        switch config.quoting {
        case .none: quote.selectItem(at: 2)
        case .character(let c, let escaping): quote.selectItem(at: escaping == .backslash ? 3 : c == "'" ? 1 : 0)
        }
        decimal.selectItem(at: config.decimalMark == .point ? 0 : 1)
        header.state = config.firstRowAsHeader ? .on : .off
        status.stringValue = "\(document.model.visibleRowCount) 行 · \(document.model.columnOrder.count) 列  \(detectionNotice)"
        isReloading = false
        updateActions()
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateActions() }
    private func updateActions() {
        for button in actionButtons {
            switch button.action {
            case #selector(deleteRows(_:)): button.isEnabled = !tableView.selectedRowIndexes.isEmpty
            case #selector(deleteColumns(_:)): button.isEnabled = !tableView.selectedColumnIndexes.isEmpty
            case #selector(editHeader(_:)): button.isEnabled = document.configuration.firstRowAsHeader && !tableView.selectedColumnIndexes.isEmpty && !document.model.table.rows.isEmpty
            default: button.isEnabled = true
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { document.model.visibleRowCount }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let index = tableView.tableColumns.firstIndex(of: column) else { return nil }
        let field = NSTextField(string: document.model.literal(row: row, column: index))
        field.isBordered = false; field.drawsBackground = false
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier("\(row):\(index)")
        return field
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === delimiter { formatChanged(field); return }
        guard let parts = field.identifier?.rawValue.split(separator: ":"), parts.count == 2,
              let row = Int(parts[0]), let column = Int(parts[1]) else { return }
        document.applyChange("编辑单元格") { $0.edit(row: row, column: column, literal: field.stringValue) }
    }
    @objc private func formatChanged(_ sender: Any?) {
        guard !isReloading else { return }
        var config = document.configuration
        config.encoding = CSVEncoding.allCases[encoding.indexOfSelectedItem]
        let text = delimiter.stringValue == "\\t" ? "\t" : delimiter.stringValue
        guard text.unicodeScalars.count == 1, let char = text.first else { show(CSVError.invalidConfiguration("分隔符必须为一个字符；Tab使用\\t。")); reload(); return }
        config.delimiter = char
        switch quote.indexOfSelectedItem {
        case 1: config.quoting = .character("'", escaping: .doubledQuote)
        case 2: config.quoting = .none
        case 3: config.quoting = .character("\"", escaping: .backslash)
        default: config.quoting = .character("\"", escaping: .doubledQuote)
        }
        config.decimalMark = decimal.indexOfSelectedItem == 0 ? .point : .comma
        config.firstRowAsHeader = header.state == .on
        do { try document.reinterpret(config) } catch { show(error); reload() }
    }
    private func show(_ error: Error) { NSAlert(error: error).runModal() }
    private func change(_ title: String, _ body: (inout GridModel) -> Void) {
        guard document.commitPendingEditing() else { return }
        document.applyChange(title, body)
    }
    @objc func insertRow(_ sender: Any?) {
        let index = tableView.selectedRowIndexes.first ?? document.model.visibleRowCount
        change("插入行") { $0.insertRows(at: index) }
    }
    @objc func deleteRows(_ sender: Any?) {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        change("删除行") { $0.deleteRows(indexes) }
    }
    @objc func insertColumn(_ sender: Any?) {
        let index = tableView.selectedColumnIndexes.first ?? document.model.columnOrder.count
        change("插入列") { $0.insertColumn(at: index) }
    }
    @objc func deleteColumns(_ sender: Any?) {
        let indexes = tableView.selectedColumnIndexes
        guard !indexes.isEmpty else { return }
        change("删除列") { $0.deleteColumns(indexes) }
    }
    @objc func editHeader(_ sender: Any?) {
        guard document.configuration.firstRowAsHeader, let c = tableView.selectedColumnIndexes.first, !document.model.table.rows.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "编辑表头"
        let field = NSTextField(string: document.model.title(column: c)); field.frame.size = NSSize(width: 300, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        change("编辑表头") { model in
            let index = model.storageColumnOrder[c]
            while model.table.rows[0].count <= index { model.table.rows[0].append(CSVCell(literal: "")) }
            model.table.rows[0][index] = CSVCell(literal: field.stringValue)
        }
    }
    @objc func copy(_ sender: Any?) { _ = copySelection() }
    private func copySelection() -> Bool {
        guard !tableView.selectedRowIndexes.isEmpty || !tableView.selectedColumnIndexes.isEmpty,
              document.commitPendingEditing() else { return false }
        do {
            let text = try exchangeText(rows: tableView.selectedRowIndexes, columns: tableView.selectedColumnIndexes)
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        } catch { show(error); return false }
    }
    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        do {
            let result = try CSVReader().read(Data(text.utf8), configuration: CSVConfiguration(delimiter: "\t"))
            let values = result.table.rows.map { $0.map(\.literal) }
            let index = tableView.selectedRowIndexes.first ?? document.model.visibleRowCount
            change("粘贴行") { $0.insertRows(at: index, values: values) }
        } catch { show(error) }
    }
    private func exchangeText(rows: IndexSet, columns: IndexSet = []) throws -> String {
        let data = try CSVWriter().write(document.model.selectedTable(rows: rows, columns: columns), configuration: CSVConfiguration(delimiter: "\t"), options: CSVWriteOptions())
        guard let text = String(data: data, encoding: .utf8) else { throw CSVError.decodingFailed(.utf8) }
        return text
    }
    @objc private func columnMoved(_ note: Notification) {
        guard !isReloading, let from = note.userInfo?["NSOldColumn"] as? Int, let to = note.userInfo?["NSNewColumn"] as? Int else { return }
        change("移动列") { $0.moveColumn(from: from, to: to) }
    }
    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard document.commitPendingEditing() else { return false }
        do {
            let text = try exchangeText(rows: rowIndexes)
            pasteboard.declareTypes([rowPasteboardType, .string], owner: nil)
            pasteboard.setPropertyList(["document": dragIdentity, "rows": Array(rowIndexes)], forType: rowPasteboardType)
            pasteboard.setString(text, forType: .string)
            return true
        } catch { show(error); return false }
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above, row >= 0,
              let value = info.draggingPasteboard.propertyList(forType: rowPasteboardType) as? [String: Any],
              value["document"] as? String == dragIdentity else { return [] }
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let value = info.draggingPasteboard.propertyList(forType: rowPasteboardType) as? [String: Any],
              value["document"] as? String == dragIdentity, let rows = value["rows"] as? [Int] else { return false }
        change("移动行") { $0.moveRows(IndexSet(rows), to: row) }
        return true
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(deleteRows(_:)): return !tableView.selectedRowIndexes.isEmpty
        case #selector(deleteColumns(_:)): return !tableView.selectedColumnIndexes.isEmpty
        case #selector(copy(_:)): return !tableView.selectedRowIndexes.isEmpty || !tableView.selectedColumnIndexes.isEmpty
        case #selector(editHeader(_:)): return document.configuration.firstRowAsHeader && !tableView.selectedColumnIndexes.isEmpty && !document.model.table.rows.isEmpty
        case #selector(paste(_:)): return !(NSPasteboard.general.string(forType: .string) ?? "").isEmpty
        default: return true
        }
    }
}
