import Foundation

public struct CSVWriter: CSVWriting {
    public init() {}

    public func write(_ table: CSVTable, configuration: CSVConfiguration,
                      options: CSVWriteOptions = CSVWriteOptions()) throws -> Data {
        try configuration.validate()
        let width = table.columnCount
        let order = options.columnOrder ?? Array(0..<width)
        guard order.count == width, Set(order) == Set(0..<width) else { throw CSVError.invalidColumnOrder }
        var records: [String] = []
        for (rowIndex, row) in table.rows.enumerated() {
            guard width > 0 else {
                throw CSVError.invalidConfiguration("A zero-field row has no lossless CSV representation")
            }
            let indices = order
            var fields: [String] = []
            for columnIndex in indices {
                var literal = columnIndex < row.count ? row[columnIndex].literal : ""
                if case .convertDecimalMark(let source) = options.literalPolicy {
                    literal = CSVNumber.convert(literal, from: source, to: configuration.decimalMark)
                }
                _ = try encodeFieldForValidation(literal, configuration: configuration, row: rowIndex, column: columnIndex)
                switch configuration.quoting {
                case .none:
                    guard !literal.contains(configuration.delimiter), !literal.contains("\r"), !literal.contains("\n"),
                          !(indices.count == 1 && literal.isEmpty) else {
                        throw CSVError.malformedField(CSVSourceLocation(line: rowIndex + 1, column: columnIndex + 1),
                                                      reason: "Field cannot be represented without quoting")
                    }
                    fields.append(literal)
                case let .character(character, escaping):
                    let quote = String(character)
                    let escaped: String
                    switch escaping {
                    case .doubledQuote: escaped = literal.replacingOccurrences(of: quote, with: quote + quote)
                    case .backslash:
                        escaped = literal.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: quote, with: "\\" + quote)
                    }
                    fields.append(quote + escaped + quote)
                }
            }
            records.append(fields.joined(separator: String(configuration.delimiter)))
        }
        var text = records.joined(separator: options.serialization.lineEnding.rawValue)
        if !records.isEmpty && options.serialization.hasFinalLineEnding { text += options.serialization.lineEnding.rawValue }
        return try CSVCodec.encode(text, encoding: configuration.encoding, bom: options.serialization.hasByteOrderMark)
    }

    private func encodeFieldForValidation(_ text: String, configuration: CSVConfiguration, row: Int, column: Int) throws -> Data {
        do { return try CSVCodec.encode(text, encoding: configuration.encoding, bom: false) }
        catch { throw CSVError.encodingFailed(configuration.encoding, row: row + 1, column: column + 1) }
    }
}
