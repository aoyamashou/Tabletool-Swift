import Foundation

public struct CSVReader: CSVReading {
    public init() {}
    static let unclosedQuoteReason = "Unclosed quoted field"

    public func read(_ data: Data, configuration: CSVConfiguration) throws -> CSVReadResult {
        try configuration.validate()
        let (text, bom) = try CSVCodec.decode(data, encoding: configuration.encoding)
        let scalars = Array(text.unicodeScalars)
        let delimiter = configuration.delimiter.unicodeScalars.first!
        let quote: Unicode.Scalar?
        let backslash: Bool
        switch configuration.quoting {
        case .none: quote = nil; backslash = false
        case let .character(character, escaping):
            quote = character.unicodeScalars.first; backslash = escaping == .backslash
        }
        enum State { case start, unquoted, quoted, afterQuote }
        var state = State.start
        var rows: [[CSVCell]] = []
        var row: [CSVCell] = []
        var value = String.UnicodeScalarView()
        var i = 0, line = 1, column = 1
        var firstLineEnding: CSVLineEnding?
        var endedWithRecordSeparator = false
        func location() -> CSVSourceLocation { CSVSourceLocation(line: line, column: column) }
        func fail(_ reason: String) -> CSVError { .malformedField(location(), reason: reason) }
        func consume() {
            let scalar = scalars[i]
            if scalar == "\r" { line += 1; column = 1 }
            else if scalar == "\n" {
                if i == 0 || scalars[i - 1] != "\r" { line += 1 }
                column = 1
            } else { column += 1 }
            i += 1
        }
        func finishField() {
            let literal = String(value)
            row.append(CSVCell(literal: literal, decimal: CSVNumber.decimal(literal, mark: configuration.decimalMark)))
            value = String.UnicodeScalarView()
            state = .start
        }
        while i < scalars.count {
            let scalar = scalars[i]
            endedWithRecordSeparator = false
            if state == .quoted {
                if backslash && scalar == "\\" {
                    consume()
                    guard i < scalars.count else { throw fail("Dangling escape") }
                    // Escape a quote or a backslash; unknown escapes are malformed, never silently dropped.
                    guard scalars[i] == quote || scalars[i] == "\\" else { throw fail("Invalid escape") }
                    value.append(scalars[i]); consume()
                } else if scalar == quote {
                    consume()
                    if !backslash && i < scalars.count && scalars[i] == quote {
                        value.append(scalar); consume()
                    } else { state = .afterQuote }
                } else { value.append(scalar); consume() }
                continue
            }
            if scalar == delimiter {
                finishField(); consume(); continue
            }
            if scalar == "\r" || scalar == "\n" {
                let ending: CSVLineEnding = scalar == "\r" ?
                    ((i + 1 < scalars.count && scalars[i + 1] == "\n") ? .crlf : .cr) : .lf
                if firstLineEnding == nil { firstLineEnding = ending }
                finishField(); rows.append(row); row = []
                consume()
                if ending == .crlf { consume() }
                endedWithRecordSeparator = true
                continue
            }
            switch state {
            case .start:
                if scalar == quote { state = .quoted; consume() }
                else { state = .unquoted; value.append(scalar); consume() }
            case .unquoted:
                if scalar == quote { throw fail("Quote inside an unquoted field") }
                value.append(scalar); consume()
            case .afterQuote: throw fail("Unexpected text after closing quote")
            case .quoted: break
            }
        }
        if state == .quoted { throw fail(Self.unclosedQuoteReason) }
        if !scalars.isEmpty && !endedWithRecordSeparator { finishField(); rows.append(row) }
        return CSVReadResult(table: CSVTable(rows: rows), configuration: configuration,
                             serialization: CSVSerialization(lineEnding: firstLineEnding ?? .lf,
                                                             hasFinalLineEnding: endedWithRecordSeparator,
                                                             hasByteOrderMark: bom))
    }
}
