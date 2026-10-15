import AppKit
import CSVCore
import UniformTypeIdentifiers

extension CSVDocument {
    @objc func convertFormat(_ sender: Any?) {
        guard commitPendingEditing() else { return }
        let encoding = NSPopUpButton()
        encoding.addItems(withTitles: CSVEncoding.allCases.map(\.rawValue))
        encoding.selectItem(withTitle: configuration.encoding.rawValue)
        let delimiter = NSTextField(string: configuration.delimiter == "\t" ? "\\t" : String(configuration.delimiter))
        let quote = NSPopUpButton()
        quote.addItems(withTitles: ["双引号", "单引号", "无引用", "双引号 / 反斜杠"])
        switch configuration.quoting {
        case .none: quote.selectItem(at: 2)
        case let .character(c, escaping): quote.selectItem(at: escaping == .backslash ? 3 : c == "'" ? 1 : 0)
        }
        let decimal = NSPopUpButton(); decimal.addItems(withTitles: ["小数点 .", "小数逗号 ,"])
        decimal.selectItem(at: configuration.decimalMark == .point ? 0 : 1)
        let newline = NSPopUpButton(); newline.addItems(withTitles: ["LF", "CRLF", "CR"])
        newline.selectItem(at: serialization.lineEnding == .lf ? 0 : serialization.lineEnding == .crlf ? 1 : 2)
        let controls = NSStackView(views: [NSTextField(labelWithString: "编码"), encoding,
                                          NSTextField(labelWithString: "分隔符（Tab填\\t）"), delimiter,
                                          quote, decimal, newline])
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 6
        controls.frame = NSRect(x: 0, y: 0, width: 350, height: 230)
        let alert = NSAlert(); alert.messageText = "转换格式并导出副本"
        alert.informativeText = "当前文档与输入格式会保留。小数转换仅处理符合源数字语法的单元格。"
        alert.accessoryView = controls
        alert.addButton(withTitle: "选择导出位置…"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let delimiterText = delimiter.stringValue == "\\t" ? "\t" : delimiter.stringValue
        guard delimiterText.unicodeScalars.count == 1, let delimiterCharacter = delimiterText.first else {
            NSAlert(error: CSVError.invalidConfiguration("分隔符必须是一个字符。")).runModal(); return
        }
        var target = configuration
        target.encoding = CSVEncoding.allCases[encoding.indexOfSelectedItem]
        target.delimiter = delimiterCharacter
        target.decimalMark = decimal.indexOfSelectedItem == 0 ? .point : .comma
        switch quote.indexOfSelectedItem {
        case 1: target.quoting = .character("'", escaping: .doubledQuote)
        case 2: target.quoting = .none
        case 3: target.quoting = .character("\"", escaping: .backslash)
        default: target.quoting = .character("\"", escaping: .doubledQuote)
        }
        var output = serialization
        output.lineEnding = [CSVLineEnding.lf, .crlf, .cr][newline.indexOfSelectedItem]
        if ![CSVEncoding.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian].contains(target.encoding) {
            output.hasByteOrderMark = false
        }
        do { try target.validate() } catch { NSAlert(error: error).runModal(); return }
        let panel = NSSavePanel()
        panel.title = "导出转换后的副本"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(fileURL?.deletingPathExtension().lastPathComponent ?? "未命名")-转换.csv"
        guard panel.runModal() == .OK else { return }
        do { try exportConverted(to: panel.url, configuration: target, serialization: output) }
        catch { NSAlert(error: error).runModal() }
    }
}
