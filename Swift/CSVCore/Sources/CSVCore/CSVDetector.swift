import Foundation

/// Heuristic suggestions only: the original bytes must remain available for manual correction.
public struct CSVDetector: CSVDetecting {
    private let reader: any CSVReading

    public init(reader: any CSVReading = CSVReader()) { self.reader = reader }

    public func detect(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult {
        var candidates: [CSVDetectionCandidate] = []
        var seen: [CSVEncoding] = []
        for encoding in encodings where !seen.contains(encoding) {
            seen.append(encoding)
            for var configuration in Self.formats(encoding: encoding) {
                let result: CSVReadResult
                do {
                    // Read the entire input: a valid prefix cannot hide a damaged suffix.
                    result = try reader.read(data, configuration: configuration)
                } catch let error as CSVError {
                    switch error {
                    case .decodingFailed, .unsupportedEncoding, .malformedField: continue
                    default: throw error
                    }
                }
                let rows = Array(result.table.rows.prefix(5))
                let width = rows.first?.count ?? 0
                let equalWidths = !rows.isEmpty && rows.allSatisfy { $0.count == width }
                let numbers = rows.flatMap { $0 }.filter {
                    Self.isNumber($0.literal, mark: configuration.decimalMark)
                }.count
                let firstHasNumberOrEmpty = rows.first?.contains {
                    $0.literal.isEmpty || Self.isNumber($0.literal, mark: configuration.decimalMark)
                } ?? true
                configuration.firstRowAsHeader = equalWidths && !firstHasNumberOrEmpty
                // Retain the legacy first-five-record scoring and stable format preference.
                let widthScore = rows.dropFirst().reduce(0) {
                    $0 + ($1.count <= width ? $1.count : 0)
                }
                let score = Double(rows.count + widthScore + (equalWidths ? 5 : 0) + min(numbers, 5))
                let reasons = [
                    "编码 \(encoding.rawValue) 严格读取成功；编码优先顺序由调用方提供。",
                    "前 \(rows.count) 条记录，首行 \(width) 列；\(equalWidths ? "列数一致" : "存在不齐列")。",
                    "符合\(configuration.decimalMark.rawValue)小数语法的单元格 \(numbers) 个。",
                    "表头仅按首行空值、数值和列数推断，可手动纠正。"
                ]
                candidates.append(.init(configuration: configuration, score: score, reasons: reasons))
                // Header presence cannot be established from syntax. Keep both interpretations.
                var alternate = configuration
                alternate.firstRowAsHeader.toggle()
                candidates.append(.init(configuration: alternate, score: score - 0.25,
                                        reasons: reasons + ["备选表头解释；不会删除首行。 "]))
            }
        }
        // Explicit index tie-break makes equal scores deterministic, including encoding preference.
        let sorted = candidates.enumerated().sorted {
            $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score
        }.map(\.element)
        // Every successful parse has a plausible alternate header interpretation.
        return CSVDetectionResult(candidates: sorted, isAmbiguous: !sorted.isEmpty)
    }

    private static func isNumber(_ literal: String, mark: CSVDecimalMark) -> Bool {
        let separator = mark == .point ? "\\." : ","
        let pattern = "^[+-]?(?:[0-9]+(?:\(separator)[0-9]*)?|\(separator)[0-9]+)(?:[eE][+-]?[0-9]+)?$"
        return literal.range(of: pattern, options: .regularExpression) != nil
    }

    private static func formats(encoding: CSVEncoding) -> [CSVConfiguration] {
        let doubled: CSVQuoting = .character("\"", escaping: .doubledQuote)
        let backslash: CSVQuoting = .character("\"", escaping: .backslash)
        // Legacy config1,10,6,2,5,7,3,8,4,9,11, then extra plausible variants.
        let formats: [(Character, CSVQuoting, CSVDecimalMark)] = [
            (",", doubled, .point), (",", backslash, .point), (",", .none, .point),
            (";", doubled, .comma), (";", backslash, .comma), (";", .none, .comma),
            ("\t", doubled, .point), ("\t", .none, .point),
            ("\t", doubled, .comma), ("\t", .none, .comma), (",", doubled, .comma),
            (";", doubled, .point), (";", backslash, .point), (";", .none, .point),
            ("\t", backslash, .point), ("\t", backslash, .comma),
            (",", backslash, .comma), (",", .none, .comma)
        ]
        return formats.map { CSVConfiguration(encoding: encoding, delimiter: $0.0,
                                               quoting: $0.1, decimalMark: $0.2) }
    }
}
