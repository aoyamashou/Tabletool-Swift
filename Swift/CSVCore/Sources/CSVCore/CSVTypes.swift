import Foundation

/// Decoded field content, excluding CSV quoting/escaping. Never regenerate it from a number.
public struct CSVCell: Equatable, Sendable {
    public let literal: String
    /// Optional exact interpretation. Leave nil when Decimal cannot represent the entire value.
    public let decimal: Decimal?

    public init(literal: String, decimal: Decimal? = nil) {
        self.literal = literal
        self.decimal = decimal
    }
}

/// Ragged rows are intentional. A missing field is distinct from an explicit empty field.
/// Header, when enabled, remains row zero; UI adapters own stable row/column identifiers.
public struct CSVTable: Equatable, Sendable {
    public var rows: [[CSVCell]]
    public var columnCount: Int { rows.map(\.count).max() ?? 0 }

    public init(rows: [[CSVCell]] = []) { self.rows = rows }
}

public enum CSVEncoding: String, CaseIterable, Sendable {
    case utf8, macRoman, windows1252, gbk, isoLatin2, windows1250
    case windows1251, windows1253, windows1254, japaneseEUC, shiftJIS, iso2022JP
    case utf16, utf16BigEndian, utf16LittleEndian, utf32, utf32BigEndian, utf32LittleEndian
    /// Detector candidate used by the legacy Chinese fixtures; distinct from GBK.
    case gb18030
}

public enum CSVEscaping: String, Sendable { case doubledQuote, backslash }
public enum CSVQuoting: Equatable, Sendable {
    case none
    case character(Character, escaping: CSVEscaping)
}
public enum CSVDecimalMark: String, Sendable { case point = ".", comma = "," }
public enum CSVLineEnding: String, Sendable { case lf = "\n", crlf = "\r\n", cr = "\r" }

public struct CSVConfiguration: Equatable, Sendable {
    public var encoding: CSVEncoding
    public var delimiter: Character
    public var quoting: CSVQuoting
    public var decimalMark: CSVDecimalMark
    public var firstRowAsHeader: Bool

    public init(encoding: CSVEncoding = .utf8, delimiter: Character = ",",
                quoting: CSVQuoting = .character("\"", escaping: .doubledQuote),
                decimalMark: CSVDecimalMark = .point, firstRowAsHeader: Bool = false) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.quoting = quoting
        self.decimalMark = decimalMark
        self.firstRowAsHeader = firstRowAsHeader
    }

    public func validate() throws {
        guard delimiter.unicodeScalars.count == 1,
              !delimiter.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) else {
            throw CSVError.invalidConfiguration("Delimiter must be one non-newline scalar")
        }
        if case let .character(quote, escaping) = quoting {
            guard quote != delimiter, quote.unicodeScalars.count == 1,
                  !quote.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }),
                  !(escaping == .backslash && (quote == "\\" || delimiter == "\\")) else {
                throw CSVError.invalidConfiguration("Quote, delimiter and escape conflict")
            }
        }
    }
}

/// Transport syntax tracked separately from decoded field values.
public struct CSVSerialization: Equatable, Sendable {
    public var lineEnding: CSVLineEnding
    public var hasFinalLineEnding: Bool
    public var hasByteOrderMark: Bool
    public init(lineEnding: CSVLineEnding = .lf, hasFinalLineEnding: Bool = false,
                hasByteOrderMark: Bool = false) {
        self.lineEnding = lineEnding
        self.hasFinalLineEnding = hasFinalLineEnding
        self.hasByteOrderMark = hasByteOrderMark
    }
}

/// One-based physical line and Unicode-scalar column, not byte offset or table cell index.
public struct CSVSourceLocation: Equatable, Sendable {
    public let line: Int
    public let column: Int
    public init(line: Int, column: Int) { self.line = line; self.column = column }
}

public enum CSVError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case decodingFailed(CSVEncoding)
    case malformedField(CSVSourceLocation, reason: String)
    case encodingFailed(CSVEncoding, row: Int?, column: Int?)
    case invalidColumnOrder
    case unsupportedEncoding(CSVEncoding)
    case notImplemented(String)
}

extension CSVError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): return "CSV配置无效：\(reason)"
        case .decodingFailed(let encoding): return "无法按\(encoding.rawValue)严格解码文件。"
        case .malformedField(let location, let reason):
            return "第\(location.line)行、第\(location.column)列：\(reason)"
        case .encodingFailed(let encoding, let row, let column):
            return "无法用\(encoding.rawValue)无损编码（行：\(row.map(String.init) ?? "未知")，列：\(column.map(String.init) ?? "未知")）。"
        case .invalidColumnOrder: return "显示列顺序无效。"
        case .unsupportedEncoding(let encoding): return "暂不支持编码：\(encoding.rawValue)。"
        case .notImplemented(let feature): return "尚未实现：\(feature)。"
        }
    }
}
