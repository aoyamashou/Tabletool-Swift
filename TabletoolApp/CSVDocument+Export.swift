import AppKit
import CSVCore
import UniformTypeIdentifiers

extension CSVDocument {
    @objc func convertFormat(_ sender: Any?) {
        guard commitPendingEditing() else { return }
        let encoding = NSPopUpButton()
        encoding.addItems(withTitles: CSVEncoding.allCases.map(\.displayName))
        encoding.selectItem(at: CSVEncoding.allCases.firstIndex(of: configuration.encoding) ?? 0)
        let delimiter = NSTextField(string: configuration.delimiter == "\t" ? "\\t" : String(configuration.delimiter))
        let quote = NSPopUpButton()
        quote.addItems(withTitles: [tr("Double quote"), tr("Single quote"), tr("No quoting"), tr("Double quote / backslash")])
        switch configuration.quoting {
        case .none: quote.selectItem(at: 2)
        case let .character(c, escaping): quote.selectItem(at: escaping == .backslash ? 3 : c == "'" ? 1 : 0)
        }
        let decimal = NSPopUpButton(); decimal.addItems(withTitles: [tr("Decimal point ."), tr("Decimal comma ,")])
        decimal.selectItem(at: configuration.decimalMark == .point ? 0 : 1)
        let newline = NSPopUpButton(); newline.addItems(withTitles: ["LF", "CRLF", "CR"])
        newline.selectItem(at: serialization.lineEnding == .lf ? 0 : serialization.lineEnding == .crlf ? 1 : 2)
        let controls = NSStackView(views: [NSTextField(labelWithString: tr("Encoding")), encoding,
                                          NSTextField(labelWithString: tr("Delimiter (enter \\t for Tab)")), delimiter,
                                          quote, decimal, newline])
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 6
        controls.frame = NSRect(x: 0, y: 0, width: 350, height: 230)
        let alert = NSAlert(); alert.messageText = tr("Convert Format and Export Copy")
        alert.informativeText = tr("The current document and its input format are kept. Decimal conversion only affects cells that match the source number syntax.")
        alert.accessoryView = controls
        alert.addButton(withTitle: tr("Choose Export Location…")); alert.addButton(withTitle: tr("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let delimiterText = delimiter.stringValue == "\\t" ? "\t" : delimiter.stringValue
        guard delimiterText.unicodeScalars.count == 1, let delimiterCharacter = delimiterText.first else {
            NSAlert(error: CSVError.invalidConfiguration(tr("The delimiter must be a single character."))).runModal(); return
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
        panel.title = tr("Export Converted Copy")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = tr("%@-converted.csv", fileURL?.deletingPathExtension().lastPathComponent ?? tr("Untitled"))
        guard panel.runModal() == .OK else { return }
        do { try exportConverted(to: panel.url, configuration: target, serialization: output) }
        catch { NSAlert(error: error).runModal() }
    }
}
