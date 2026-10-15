import Foundation

public struct CSVReadResult: Equatable, Sendable {
    public let table: CSVTable
    public let configuration: CSVConfiguration
    public let serialization: CSVSerialization
    public init(table: CSVTable, configuration: CSVConfiguration, serialization: CSVSerialization) {
        self.table = table; self.configuration = configuration; self.serialization = serialization
    }
}

public enum CSVLiteralPolicy: Equatable, Sendable {
    case preserve
    /// Explicit conversion of numeric syntax only; operate on the literal, never through Double.
    case convertDecimalMark(from: CSVDecimalMark)
}

public struct CSVWriteOptions: Equatable, Sendable {
    public var serialization: CSVSerialization
    /// nil = storage order; otherwise a full permutation of 0..<table.columnCount.
    public var columnOrder: [Int]?
    public var literalPolicy: CSVLiteralPolicy
    public init(serialization: CSVSerialization = CSVSerialization(), columnOrder: [Int]? = nil,
                literalPolicy: CSVLiteralPolicy = .preserve) {
        self.serialization = serialization; self.columnOrder = columnOrder
        self.literalPolicy = literalPolicy
    }
}

public struct CSVDetectionCandidate: Equatable, Sendable {
    public let configuration: CSVConfiguration
    /// Relative score, not a probability. Multiple plausible candidates must remain selectable.
    public let score: Double
    public let reasons: [String]
    public init(configuration: CSVConfiguration, score: Double, reasons: [String]) {
        self.configuration = configuration; self.score = score; self.reasons = reasons
    }
}

public struct CSVDetectionResult: Equatable, Sendable {
    /// Best first. Empty means no supported interpretation, never silent fallback decoding.
    public let candidates: [CSVDetectionCandidate]
    public let isAmbiguous: Bool
    /// Full-file read already performed while validating the best candidate (large inputs only).
    /// Lets callers skip a second pass; use `readResult(for:)` to reuse it safely.
    public let validatedRead: CSVReadResult?
    public init(candidates: [CSVDetectionCandidate], isAmbiguous: Bool, validatedRead: CSVReadResult? = nil) {
        self.candidates = candidates; self.isAmbiguous = isAmbiguous; self.validatedRead = validatedRead
    }

    /// The cached full read, re-labelled with `configuration`, when it parses identically
    /// (only the header flag may differ: the table never depends on it).
    public func readResult(for configuration: CSVConfiguration) -> CSVReadResult? {
        guard let read = validatedRead else { return nil }
        var cached = read.configuration
        cached.firstRowAsHeader = configuration.firstRowAsHeader
        guard cached == configuration else { return nil }
        return CSVReadResult(table: read.table, configuration: configuration, serialization: read.serialization)
    }
}

/// T2 implements CSVReader and CSVWriter; these pure operations do not access the filesystem.
public protocol CSVReading {
    func read(_ data: Data, configuration: CSVConfiguration) throws -> CSVReadResult
}
public protocol CSVWriting {
    func write(_ table: CSVTable, configuration: CSVConfiguration, options: CSVWriteOptions) throws -> Data
}
/// T3 implements CSVDetector, independent of the concrete reader via CSVReading injection.
public protocol CSVDetecting {
    func detect(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult
}
