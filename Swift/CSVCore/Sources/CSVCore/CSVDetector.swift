import Foundation

/// Heuristic suggestions only: the original bytes must remain available for manual correction.
public struct CSVDetector: CSVDetecting {
    private let reader: any CSVReading

    public init(reader: any CSVReading = CSVReader()) { self.reader = reader }

    /// Inputs up to this size keep the exhaustive behaviour: every candidate reads the whole file.
    static let sampleThreshold = 256 * 1024
    /// Growing prefix sizes used to score large inputs; scoring only looks at the first five records.
    private static let sampleSizes = [4 * 1024, 16 * 1024, 64 * 1024, 256 * 1024, 1024 * 1024]

    public func detect(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult {
        data.count <= Self.sampleThreshold ? try detectExhaustively(data, encodings: encodings)
                                           : try detectBySampling(data, encodings: encodings)
    }

    private func detectExhaustively(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult {
        var candidates: [CSVDetectionCandidate] = []
        var seen: [CSVEncoding] = []
        for encoding in encodings where !seen.contains(encoding) {
            seen.append(encoding)
            for configuration in Self.formats(encoding: encoding) {
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
                candidates += Self.candidates(from: result, configuration: configuration, encoding: encoding)
            }
        }
        return CSVDetectionResult(candidates: Self.ranked(candidates), isAmbiguous: !candidates.isEmpty)
    }

    /// Large inputs: score every encoding/format on a small line-aligned prefix, then strictly read the
    /// whole file only for the best candidates (until one succeeds). The winning full read is returned
    /// so the caller does not parse the file again.
    private func detectBySampling(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult {
        var candidates: [CSVDetectionCandidate] = []
        var seen: [CSVEncoding] = []
        for encoding in encodings where !seen.contains(encoding) {
            seen.append(encoding)
            var cuts: [Int: Data?] = [:] // line-aligned prefixes are shared by every format of an encoding
            for configuration in Self.formats(encoding: encoding) {
                guard let result = try sampledRead(data, configuration: configuration, cuts: &cuts) else { continue }
                candidates += Self.candidates(from: result, configuration: configuration, encoding: encoding)
            }
        }
        var ranked = Self.ranked(candidates)
        var verified: [String: CSVReadResult?] = [:]
        var winner: CSVReadResult?
        var kept: [CSVDetectionCandidate] = []
        var index = 0
        while index < ranked.count {
            let candidate = ranked[index]; index += 1
            var key = candidate.configuration; key.firstRowAsHeader = false
            let cacheKey = "\(key.encoding.rawValue)|\(key.delimiter)|\(key.quoting)|\(key.decimalMark.rawValue)"
            let full: CSVReadResult?
            if let cached = verified[cacheKey] { full = cached } else {
                do { full = try reader.read(data, configuration: key) }
                catch let error as CSVError {
                    switch error {
                    case .decodingFailed, .unsupportedEncoding, .malformedField: full = nil
                    default: throw error
                    }
                }
                verified[cacheKey] = full
            }
            guard let full else { continue }
            winner = full
            kept.append(.init(configuration: candidate.configuration, score: candidate.score,
                              reasons: candidate.reasons + ["已对整个文件严格读取验证。"]))
            // Lower-ranked candidates stay selectable; they are only scored on the sample.
            kept += ranked[index...].map {
                .init(configuration: $0.configuration, score: $0.score,
                      reasons: $0.reasons + ["仅按文件前部采样评分，尚未对整个文件验证。"])
            }
            break
        }
        ranked = kept
        return CSVDetectionResult(candidates: ranked, isAmbiguous: !ranked.isEmpty, validatedRead: winner)
    }

    /// Reads a growing line-aligned prefix until it holds five complete records. Returns nil when the
    /// candidate cannot decode or parse. An unclosed quote at the cut only means the prefix was too short.
    private func sampledRead(_ data: Data, configuration: CSVConfiguration,
                             cuts: inout [Int: Data?]) throws -> CSVReadResult? {
        // Wide encodings decode ASCII bytes into garbage "successfully"; without a code-unit-aligned line
        // break in the prefix they are not worth a whole-file read.
        let wide = [.utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian]
            .contains(configuration.encoding)
        for size in wide ? Self.sampleSizes : Self.sampleSizes + [data.count] {
            let isWhole = size >= data.count
            let sample: Data
            if isWhole { sample = data }
            else {
                if cuts[size] == nil { cuts[size] = .some(Self.lineAlignedPrefix(data, limit: size, encoding: configuration.encoding)) }
                guard let cut = cuts[size]! else { continue }
                sample = cut
            }
            do {
                let result = try reader.read(sample, configuration: configuration)
                if isWhole || result.table.rows.count >= 6 { return result }
            } catch let error as CSVError {
                switch error {
                case .malformedField(_, let reason) where !isWhole && reason == CSVReader.unclosedQuoteReason: continue
                case .decodingFailed, .unsupportedEncoding, .malformedField: return nil
                default: throw error
                }
            }
        }
        return nil
    }

    /// Longest prefix of at most `limit` bytes that ends right after a line feed (or carriage return)
    /// code unit, aligned to the encoding's code-unit width.
    static func lineAlignedPrefix(_ data: Data, limit: Int, encoding: CSVEncoding) -> Data? {
        let unit: Int, little: Bool
        switch encoding {
        case .utf16, .utf16BigEndian, .utf16LittleEndian:
            unit = 2
            little = encoding == .utf16LittleEndian || (encoding == .utf16 && data.starts(with: [0xff, 0xfe]))
        case .utf32, .utf32BigEndian, .utf32LittleEndian:
            unit = 4
            little = encoding == .utf32LittleEndian || (encoding == .utf32 && data.starts(with: [0xff, 0xfe, 0, 0]))
        default: unit = 1; little = false
        }
        let end0 = (min(limit, data.count) / unit) * unit
        let cut: Int? = data.withUnsafeBytes { raw -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            // Index of the significant byte inside a code unit; every other byte of a line break is zero.
            let main = little ? 0 : unit - 1
            for terminator: UInt8 in [0x0a, 0x0d] {
                var end = end0
                scan: while end >= unit {
                    let base = end - unit
                    if bytes[base + main] == terminator {
                        for offset in 0..<unit where offset != main && bytes[base + offset] != 0 { end -= unit; continue scan }
                        return end
                    }
                    end -= unit
                }
            }
            return nil
        }
        return cut.map { data.prefix($0) }
    }

    private static func candidates(from result: CSVReadResult, configuration: CSVConfiguration,
                                   encoding: CSVEncoding) -> [CSVDetectionCandidate] {
        var configuration = configuration
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
        // Header presence cannot be established from syntax. Keep both interpretations.
        var alternate = configuration
        alternate.firstRowAsHeader.toggle()
        return [.init(configuration: configuration, score: score, reasons: reasons),
                .init(configuration: alternate, score: score - 0.25,
                      reasons: reasons + ["备选表头解释；不会删除首行。 "])]
    }

    private static func ranked(_ candidates: [CSVDetectionCandidate]) -> [CSVDetectionCandidate] {
        // Explicit index tie-break makes equal scores deterministic, including encoding preference.
        candidates.enumerated().sorted {
            $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score
        }.map(\.element)
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
