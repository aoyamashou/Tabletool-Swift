import Foundation
import XCTest
@testable import CSVCore

final class DetectorTests: XCTestCase {
    private let western: [CSVEncoding] = [.utf8, .windows1252, .macRoman, .gb18030]

    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("Table ToolTests/Heuristic Test Documents/\(name).csv"))
    }

    private func best(_ name: String, encodings: [CSVEncoding]? = nil) throws -> CSVConfiguration {
        let result = try CSVDetector().detect(fixture(name), encodings: encodings ?? western)
        return try XCTUnwrap(result.candidates.first, name).configuration
    }

    private func assertFormat(_ name: String, delimiter: Character = ",",
                              mark: CSVDecimalMark = .point,
                              quoting: CSVQuoting = .character("\"", escaping: .doubledQuote),
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let config = try best(name)
        XCTAssertEqual(config.delimiter, delimiter, file: file, line: line)
        XCTAssertEqual(config.decimalMark, mark, file: file, line: line)
        XCTAssertEqual(config.quoting, quoting, file: file, line: line)
        XCTAssertTrue(config.firstRowAsHeader, file: file, line: line)
    }
    func testHeuristicError1() throws { try assertFormat("heuristic-comma-separated-people-1") }
    func testHeuristicError2() throws { try assertFormat("heuristic-comma-separated-people-2") }
    func testHeuristicError3() throws { try assertFormat("heuristic-comma-separated-places") }
    func testHeuristicConfig1() throws { try assertFormat("heuristic-config1") }
    func testHeuristicConfig2() throws { try assertFormat("heuristic-config2", delimiter: ";", mark: .comma) }
    func testHeuristicConfig3() throws { try assertFormat("heuristic-config3", delimiter: "\t") }
    func testHeuristicConfig4() throws { try assertFormat("heuristic-config4", delimiter: "\t", mark: .comma) }
    func testHeuristicConfig5() throws { try assertFormat("heuristic-config5", delimiter: ";", mark: .comma, quoting: .character("\"", escaping: .backslash)) }
    func testHeuristicConfig6() throws { try assertFormat("heuristic-config6", quoting: .none) }
    func testHeuristicConfig7() throws { try assertFormat("heuristic-config7", delimiter: ";", mark: .comma, quoting: .none) }
    func testHeuristicConfig8() throws { try assertFormat("heuristic-config8", delimiter: "\t", quoting: .none) }
    func testHeuristicConfig9() throws { try assertFormat("heuristic-config9", delimiter: "\t", mark: .comma, quoting: .none) }
    func testHeuristicConfig10() throws { try assertFormat("heuristic-config10", quoting: .character("\"", escaping: .backslash)) }
    func testHeuristicConfig11() throws { try assertFormat("heuristic-config11", mark: .comma) }
    func testHeuristicNoHeaderBecauseOfNumber() throws {
        XCTAssertFalse(try best("heuristic-first-row-with-number").firstRowAsHeader)
    }
    func testHeuristicNoHeaderBecauseOfShorterLength() throws {
        XCTAssertFalse(try best("heuristic-first-row-one-row-shorter").firstRowAsHeader)
    }
    func testHeuristicNoHeaderBecauseOfLongerLength() throws {
        XCTAssertFalse(try best("heuristic-first-row-longer").firstRowAsHeader)
    }
    func testHeuristicChangeEncodingToWestern() throws {
        XCTAssertEqual(try best("heuristic-no-utf-encoding").encoding, .windows1252)
    }
    func testHeuristicGBK() throws {
        // Legacy calls this GBK but actually requests GB18030. Preserve that assertion exactly.
        XCTAssertEqual(try best("heuristic-gbk", encodings: [.utf8, .gb18030, .windows1252, .macRoman]).encoding,
                       .gb18030)
    }
    func testHeuristicIssue4Sample() throws {
        let config = try best("issue-4-sample")
        XCTAssertEqual(config.encoding, .macRoman)
        XCTAssertEqual(config.delimiter, "\t")
        XCTAssertTrue(config.firstRowAsHeader)
    }

    func testAmbiguityPreservesEncodingAndHeaderAlternatives() throws {
        let result = try CSVDetector().detect(Data("name,age\nAda,20".utf8), encodings: [.utf8, .windows1252])
        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(result.candidates.first?.configuration.encoding, .utf8)
        XCTAssertTrue(result.candidates.contains { $0.configuration.encoding == .windows1252 })
        XCTAssertTrue(result.candidates.contains { !$0.configuration.firstRowAsHeader })
        XCTAssertTrue(zip(result.candidates, result.candidates.dropFirst()).allSatisfy { $0.score >= $1.score })
        XCTAssertTrue(result.candidates.allSatisfy { !$0.reasons.isEmpty })
    }
    func testNoEncodingCandidatesHasNoSolution() throws {
        let result = try CSVDetector().detect(Data("a,b".utf8), encodings: [])
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.isAmbiguous)
    }
    func testMalformedUTF8HasNoLossyFallback() throws {
        let result = try CSVDetector().detect(Data([0x61, 0x2c, 0xff]), encodings: [.utf8])
        XCTAssertTrue(result.candidates.isEmpty)
    }
    func testGBKIsDistinctFromGB18030() throws {
        let result = try CSVDetector().detect(fixture("heuristic-gbk"), encodings: [.gbk, .gb18030])
        XCTAssertEqual(result.candidates.first?.configuration.encoding, .gbk)
        XCTAssertTrue(result.candidates.contains { $0.configuration.encoding == .gb18030 })
        XCTAssertTrue(result.isAmbiguous)
        let config = try XCTUnwrap(result.candidates.first).configuration
        let read = try CSVReader().read(fixture("heuristic-gbk"), configuration: config)
        XCTAssertEqual(read.table.rows[1].map(\.literal), ["你好", "中文", "中国"])
    }
    func testDuplicateEncodingsDoNotDuplicateConfigurations() throws {
        let result = try CSVDetector().detect(Data("a,b\nc,d".utf8), encodings: [.utf8, .utf8])
        for candidate in result.candidates {
            XCTAssertEqual(result.candidates.filter { $0.configuration == candidate.configuration }.count, 1)
        }
    }
    func testInjectedReaderAndUnexpectedFailures() throws {
        struct Unsupported: CSVReading {
            func read(_ data: Data, configuration: CSVConfiguration) throws -> CSVReadResult {
                throw CSVError.unsupportedEncoding(configuration.encoding)
            }
        }
        XCTAssertTrue(try CSVDetector(reader: Unsupported()).detect(Data(), encodings: [.utf8]).candidates.isEmpty)
        struct Broken: CSVReading {
            func read(_ data: Data, configuration: CSVConfiguration) throws -> CSVReadResult {
                throw CSVError.notImplemented("reader")
            }
        }
        XCTAssertThrowsError(try CSVDetector(reader: Broken()).detect(Data(), encodings: [.utf8])) {
            XCTAssertEqual($0 as? CSVError, .notImplemented("reader"))
        }
    }
    func testEmptyAndSingleColumnRemainAmbiguous() throws {
        for text in ["", "one", "one\ntwo"] {
            let result = try CSVDetector().detect(Data(text.utf8), encodings: [.utf8])
            XCTAssertFalse(result.candidates.isEmpty)
            XCTAssertTrue(result.isAmbiguous)
        }
    }
    func testLargeNumericLiteralDoesNotBecomeHeader() throws {
        let data = Data("12345678901234567890123456789012345678901234567890,label\n2,next".utf8)
        let result = try CSVDetector().detect(data, encodings: [.utf8])
        XCTAssertEqual(result.candidates.first?.configuration.firstRowAsHeader, false)
    }

    // MARK: Large inputs are scored on a sample, then verified once on the whole file.

    private func largeCSV(delimiter: String = ",", mark: String = ".", rows: Int = 20_000) -> Data {
        var text = ["id", "name", "note", "value"].joined(separator: delimiter) + "\n"
        for i in 1...rows { text += "\(i)\(delimiter)name \(i)\(delimiter)\"quoted, text\(delimiter)\"\"x\"\"\"\(delimiter)\(i).5".replacingOccurrences(of: ".5", with: "\(mark)5") + "\n" }
        return Data(text.utf8)
    }

    func testLargeInputUsesSamplingAndMatchesSmallInputResult() throws {
        let large = largeCSV(delimiter: ";", mark: ",")
        XCTAssertGreaterThan(large.count, CSVDetector.sampleThreshold)
        let result = try CSVDetector().detect(large, encodings: CSVEncoding.allCases)
        let best = try XCTUnwrap(result.candidates.first).configuration
        XCTAssertEqual(best.encoding, .utf8)
        XCTAssertEqual(best.delimiter, ";")
        XCTAssertEqual(best.decimalMark, .comma)
        XCTAssertTrue(best.firstRowAsHeader)
        let cached = try XCTUnwrap(result.readResult(for: best))
        XCTAssertEqual(cached.table.rows.count, 20_001)
        XCTAssertEqual(cached.table, try CSVReader().read(large, configuration: best).table)
    }

    func testLargeInputScoresLikeExhaustiveDetection() throws {
        let large = largeCSV()
        let sampled = try CSVDetector().detect(large, encodings: [.utf8, .windows1252])
        // Same leading records, but below the threshold: exhaustive scoring must agree on the winner.
        let head = Data(large.prefix(upTo: large.index(large.startIndex, offsetBy: 2_000)))
        let lineEnd = try XCTUnwrap(head.lastIndex(of: 0x0a))
        let exhaustive = try CSVDetector().detect(Data(head.prefix(through: lineEnd)), encodings: [.utf8, .windows1252])
        XCTAssertEqual(sampled.candidates.first?.configuration, exhaustive.candidates.first?.configuration)
    }

    func testLargeInputWithDamagedSuffixDropsEncodingThatCannotReadItAll() throws {
        var data = largeCSV()
        data.append(contentsOf: [0xff, 0xfe, 0xfd, 0x0a]) // invalid UTF-8 near the end, invisible to a prefix sample
        let result = try CSVDetector().detect(data, encodings: [.utf8, .windows1252])
        XCTAssertEqual(result.candidates.first?.configuration.encoding, .windows1252)
        XCTAssertNotNil(result.validatedRead)
    }

    func testLargeInputWithMultilineQuotedFieldAtSampleCut() throws {
        // A quoted field with embedded newlines straddling the first sample boundary must not reject the format.
        var text = "id,note\n"
        for i in 0..<12_000 { text += "\(i),\"line one\nline two\nline three \(i)\"\n" }
        let data = Data(text.utf8)
        XCTAssertGreaterThan(data.count, CSVDetector.sampleThreshold)
        let result = try CSVDetector().detect(data, encodings: [.utf8])
        let best = try XCTUnwrap(result.candidates.first).configuration
        XCTAssertEqual(best.delimiter, ",")
        XCTAssertEqual(best.quoting, .character("\"", escaping: .doubledQuote))
        XCTAssertEqual(result.readResult(for: best)?.table.rows.count, 12_001)
    }

    func testLineAlignedPrefixHandlesWideEncodings() {
        let utf16le = Data("a,b\nc,d\ne".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        let cut = CSVDetector.lineAlignedPrefix(utf16le, limit: utf16le.count - 2, encoding: .utf16LittleEndian)
        XCTAssertEqual(cut?.count, 16) // "a,b\nc,d\n" = 8 units
        let utf16be = Data("a,b\nc,d\ne".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] })
        XCTAssertEqual(CSVDetector.lineAlignedPrefix(utf16be, limit: utf16be.count, encoding: .utf16BigEndian)?.count, 16)
        XCTAssertEqual(CSVDetector.lineAlignedPrefix(Data("a\r\rb".utf8), limit: 5, encoding: .utf8)?.count, 3)
    }

    // MARK: Legacy CJK / Western encodings are told apart by how much the decoded text looks like text.

    private func detectDecoded(_ text: String, encoded: CSVEncoding) throws -> (CSVEncoding, String) {
        let data = try CSVCodec.encode(text, encoding: encoded, bom: false)
        let result = try CSVDetector().detect(data, encodings: CSVEncoding.allCases)
        let best = try XCTUnwrap(result.candidates.first).configuration
        let read = try CSVReader().read(data, configuration: best)
        return (best.encoding, read.table.rows.map { $0.map(\.literal).joined(separator: ",") }.joined(separator: "\n") + "\n")
    }

    private let chinese = "编号,姓名,城市,备注\n1,张伟,北京,你好世界\n2,王芳,上海,表格工具\n3,李娜,广州,中文测试\n"
    private let japanese = "番号,名前,都市,備考\n1,山田太郎,東京,こんにちは世界\n2,佐藤花子,大阪,表計算ツール\n3,鈴木一郎,京都,日本語のテスト\n"
    private let latinText = "id,name,city,note\n1,Müller,München,Größe\n2,Zoë,Zürich,Straße\n3,Hervé,Bordeaux,café résumé\n"

    func testShiftJISIsNotMistakenForMacRoman() throws {
        let (encoding, text) = try detectDecoded(japanese, encoded: .shiftJIS)
        XCTAssertEqual(encoding, .shiftJIS); XCTAssertEqual(text, japanese)
    }
    func testJapaneseEUCIsNotMistakenForChinese() throws {
        let (encoding, text) = try detectDecoded(japanese, encoded: .japaneseEUC)
        XCTAssertEqual(encoding, .japaneseEUC); XCTAssertEqual(text, japanese)
    }
    func testISO2022JPIsDetected() throws {
        let (encoding, text) = try detectDecoded(japanese, encoded: .iso2022JP)
        XCTAssertEqual(encoding, .iso2022JP); XCTAssertEqual(text, japanese)
    }
    func testGBKAndGB18030TextReadAsChinese() throws {
        for encoded in [CSVEncoding.gbk, .gb18030] {
            let (encoding, text) = try detectDecoded(chinese, encoded: encoded)
            XCTAssertTrue([.gbk, .gb18030].contains(encoding), "\(encoded) detected as \(encoding)")
            XCTAssertEqual(text, chinese)
        }
    }
    func testWindows1252TextIsNotMistakenForMacRoman() throws {
        let (encoding, text) = try detectDecoded(latinText, encoded: .windows1252)
        XCTAssertEqual(encoding, .windows1252); XCTAssertEqual(text, latinText)
    }
    func testMacRomanTextStaysMacRoman() throws {
        let (encoding, text) = try detectDecoded(latinText, encoded: .macRoman)
        XCTAssertEqual(encoding, .macRoman); XCTAssertEqual(text, latinText)
    }
    func testUTF8StillWinsForNonASCIIText() throws {
        for sample in [chinese, japanese, latinText] {
            XCTAssertEqual(try detectDecoded(sample, encoded: .utf8).0, .utf8)
        }
    }
}
