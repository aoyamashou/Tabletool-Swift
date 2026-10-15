import AppKit
import CSVCore

@MainActor
final class GridViewController: NSViewController, @preconcurrency NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuItemValidation, NSToolbarDelegate, NSToolbarItemValidation {
    unowned let document: CSVDocument
    let tableView = NSTableView()
    private let encoding = NSPopUpButton()
    private let separator = NSSegmentedControl(labels: [",", ";", "⇥", "|"], trackingMode: .selectOne, target: nil, action: nil)
    private let quote = NSSegmentedControl(labels: ["\"\"", "\\\"", "无"], trackingMode: .selectOne, target: nil, action: nil)
    private let decimal = NSSegmentedControl(labels: [".", ","], trackingMode: .selectOne, target: nil, action: nil)
    private let header = NSButton(checkboxWithTitle: "表头", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private static let separators: [Character] = [",", ";", "\t", "|"]
    var detectionNotice = ""
    private let rowPasteboardType = NSPasteboard.PasteboardType("cc.kneo.TableToolSwift.rows")
    private let dragIdentity = UUID().uuidString
    private var isReloading = false
    init(document: CSVDocument) { self.document = document; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView()
        encoding.addItems(withTitles: CSVEncoding.allCases.map(\.displayName))
        for control in [separator, quote, decimal] { control.target = self; control.action = #selector(formatChanged(_:)); control.segmentStyle = .rounded }
        encoding.target = self; encoding.action = #selector(formatChanged(_:))
        header.target = self; header.action = #selector(formatChanged(_:))
        func caption(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }
        let format = NSStackView(views: [caption("编码"), encoding, caption("分隔符"), separator, caption("小数"), decimal, caption("引用"), quote, header])
        format.orientation = .horizontal
        format.spacing = 8
        for control in [encoding, separator, decimal, quote] { format.setCustomSpacing(16, after: control) }
        format.setCustomSpacing(16, after: quote)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.documentView = tableView
        tableView.dataSource = self; tableView.delegate = self
        tableView.allowsMultipleSelection = true; tableView.allowsColumnSelection = true
        tableView.allowsColumnReordering = true
        tableView.style = .fullWidth
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 4, height: 1)
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.gridColor = .separatorColor
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.registerForDraggedTypes([rowPasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        NotificationCenter.default.addObserver(self, selector: #selector(columnMoved(_:)), name: NSTableView.columnDidMoveNotification, object: tableView)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bottom = NSVisualEffectView()
        bottom.material = .windowBackground; bottom.blendingMode = .withinWindow
        for item in [format, status] { item.translatesAutoresizingMaskIntoConstraints = false; bottom.addSubview(item) }
        NSLayoutConstraint.activate([
            format.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 16),
            format.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 10),
            format.bottomAnchor.constraint(equalTo: bottom.bottomAnchor, constant: -10),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: format.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -16),
            status.centerYAnchor.constraint(equalTo: format.centerYAnchor)])
        let line = NSBox(); line.boxType = .separator
        let stack = NSStackView(views: [scroll, line, bottom])
        stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)])
        reload()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(tableView)
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
            column.headerCell.alignment = .center
            column.width = 100; column.minWidth = 50
            tableView.addTableColumn(column)
        }
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(rows.filter { $0 < document.model.visibleRowCount }), byExtendingSelection: false)
        tableView.selectColumnIndexes(IndexSet(cols.filter { $0 < document.model.columnOrder.count }), byExtendingSelection: false)
        let config = document.configuration
        encoding.selectItem(at: CSVEncoding.allCases.firstIndex(of: config.encoding) ?? 0)
        separator.selectedSegment = Self.separators.firstIndex(of: config.delimiter) ?? -1
        switch config.quoting {
        case .none: quote.selectedSegment = 2
        case .character(let c, let escaping): quote.selectedSegment = escaping == .backslash ? 1 : c == "\"" ? 0 : -1
        }
        decimal.selectedSegment = config.decimalMark == .point ? 0 : 1
        header.state = config.firstRowAsHeader ? .on : .off
        status.stringValue = "\(document.model.visibleRowCount) 行 · \(document.model.columnOrder.count) 列  \(detectionNotice)"
        isReloading = false
        updateActions()
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateActions() }
    private func updateActions() { view.window?.toolbar?.validateVisibleItems() }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .deleteRow: return !tableView.selectedRowIndexes.isEmpty
        case .deleteColumn: return !tableView.selectedColumnIndexes.isEmpty
        default: return true
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { document.model.visibleRowCount }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let index = tableView.tableColumns.firstIndex(of: column) else { return nil }
        let field = NSTextField(string: document.model.literal(row: row, column: index))
        field.isBordered = false; field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.alignment = isNumeric(field.stringValue) ? .right : .left
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier("\(row):\(index)")
        return field
    }
    private func isNumeric(_ text: String) -> Bool {
        let mark = document.configuration.decimalMark == .point ? "\\." : ","
        return text.range(of: "^[+-]?([0-9]+(\(mark)[0-9]*)?|\(mark)[0-9]+)$", options: .regularExpression) != nil
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard let parts = field.identifier?.rawValue.split(separator: ":"), parts.count == 2,
              let row = Int(parts[0]), let column = Int(parts[1]) else { return }
        document.applyChange("编辑单元格") { $0.edit(row: row, column: column, literal: field.stringValue) }
    }
    @objc private func formatChanged(_ sender: Any?) {
        guard !isReloading else { return }
        var config = document.configuration
        config.encoding = CSVEncoding.allCases[encoding.indexOfSelectedItem]
        if separator.selectedSegment >= 0 { config.delimiter = Self.separators[separator.selectedSegment] }
        switch quote.selectedSegment {
        case 0: config.quoting = .character("\"", escaping: .doubledQuote)
        case 1: config.quoting = .character("\"", escaping: .backslash)
        case 2: config.quoting = .none
        default: break
        }
        if decimal.selectedSegment >= 0 { config.decimalMark = decimal.selectedSegment == 0 ? .point : .comma }
        config.firstRowAsHeader = header.state == .on
        do { try document.reinterpret(config) } catch { show(error); reload() }
    }
    private func show(_ error: Error) { NSAlert(error: error).runModal() }
    private func change(_ title: String, _ body: (inout GridModel) -> Void) {
        guard document.commitPendingEditing() else { return }
        document.applyChange(title, body)
    }
    @objc func addRow(_ sender: NSToolbarItemGroup) {
        let rows = tableView.selectedRowIndexes
        let index = sender.selectedIndex == 0 ? (rows.first ?? 0) : (rows.last.map { $0 + 1 } ?? document.model.visibleRowCount)
        change(sender.selectedIndex == 0 ? "在上方添加行" : "在下方添加行") { $0.insertRows(at: index) }
    }
    @objc func addColumn(_ sender: NSToolbarItemGroup) {
        let columns = tableView.selectedColumnIndexes
        let index = sender.selectedIndex == 0 ? (columns.first ?? 0) : (columns.last.map { $0 + 1 } ?? document.model.columnOrder.count)
        change(sender.selectedIndex == 0 ? "在左侧添加列" : "在右侧添加列") { $0.insertColumn(at: index) }
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

extension NSToolbarItem.Identifier {
    static let addColumn = NSToolbarItem.Identifier("addColumn")
    static let deleteColumn = NSToolbarItem.Identifier("deleteColumn")
    static let addRow = NSToolbarItem.Identifier("addRow")
    static let deleteRow = NSToolbarItem.Identifier("deleteRow")
    static let convert = NSToolbarItem.Identifier("convert")
}

extension CSVEncoding {
    var displayName: String {
        switch self {
        case .utf8: "Unicode (UTF-8)"
        case .macRoman: "Western (Mac OS Roman)"
        case .windows1252: "Western (Windows Latin 1)"
        case .gbk: "Chinese (GBK)"
        case .gb18030: "Chinese (GB18030)"
        case .isoLatin2: "Central European (ISO Latin 2)"
        case .windows1250: "Central European (Windows Latin 2)"
        case .windows1251: "Cyrillic (Windows)"
        case .windows1253: "Greek (Windows)"
        case .windows1254: "Turkish (Windows Latin 5)"
        case .japaneseEUC: "Japanese (EUC)"
        case .shiftJIS: "Japanese (Shift JIS)"
        case .iso2022JP: "Japanese (ISO 2022-JP)"
        case .utf16: "Unicode (UTF-16)"
        case .utf16BigEndian: "Unicode (UTF-16BE)"
        case .utf16LittleEndian: "Unicode (UTF-16LE)"
        case .utf32: "Unicode (UTF-32)"
        case .utf32BigEndian: "Unicode (UTF-32BE)"
        case .utf32LittleEndian: "Unicode (UTF-32LE)"
        }
    }
}

/// Stripe glyphs like the original app: grey stripes with one coloured stripe (green = added, red = removed).
private func glyph(vertical: Bool, marked: Int, color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 24, height: 18), flipped: false) { _ in
        for i in 0..<5 {
            let rect = vertical ? NSRect(x: 1 + CGFloat(i) * 4.5, y: 1, width: 3, height: 16)
                                : NSRect(x: 1, y: 1 + CGFloat(i) * 3.5, width: 22, height: 2.5)
            (i == marked ? color : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
        }
        return true
    }
}

extension GridViewController {
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "TableToolSwift.main")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        return toolbar
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.addColumn, .deleteColumn, .addRow, .deleteRow, .flexibleSpace, .convert]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func group(_ title: String, _ images: [NSImage], _ tips: [String], _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .momentary, labels: tips, target: self, action: action)
            item.label = title; item.paletteLabel = title
            return item
        }
        func button(_ title: String, _ image: NSImage?, _ action: Selector, target: AnyObject?) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = title; item.paletteLabel = title; item.toolTip = title
            item.image = image; item.target = target; item.action = action
            item.isBordered = false
            return item
        }
        switch identifier {
        case .addColumn: return group("添加列", [glyph(vertical: true, marked: 0, color: .systemGreen), glyph(vertical: true, marked: 4, color: .systemGreen)], ["在左侧添加列", "在右侧添加列"], #selector(addColumn(_:)))
        case .deleteColumn: return button("删除列", glyph(vertical: true, marked: 2, color: .systemRed), #selector(deleteColumns(_:)), target: self)
        case .addRow: return group("添加行", [glyph(vertical: false, marked: 4, color: .systemGreen), glyph(vertical: false, marked: 0, color: .systemGreen)], ["在上方添加行", "在下方添加行"], #selector(addRow(_:)))
        case .deleteRow: return button("删除行", glyph(vertical: false, marked: 2, color: .systemRed), #selector(deleteRows(_:)), target: self)
        case .convert: return button("转换…", NSImage(named: NSImage.shareTemplateName), #selector(CSVDocument.convertFormat(_:)), target: nil)
        default: return nil
        }
    }
}
