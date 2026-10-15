import Foundation
import XCTest
@testable import CSVCore

final class ReaderWriterTests: XCTestCase {
    let reader = CSVReader()
    let writer = CSVWriter()
    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("Table ToolTests/Reading Test Documents/\(name).csv"))
    }
    private func read(_ text: String, _ config: CSVConfiguration = CSVConfiguration()) throws -> CSVReadResult {
        try reader.read(Data(text.utf8), configuration: config)
    }
    private func expectMalformed(_ name: String, backslash: Bool = false) throws {
        let config = CSVConfiguration(quoting: .character("\"", escaping: backslash ? .backslash : .doubledQuote))
        XCTAssertThrowsError(try reader.read(fixture(name), configuration: config)) {
            guard case .malformedField(let location, _) = $0 as? CSVError else { return XCTFail("\($0)") }
            XCTAssertGreaterThan(location.line, 0); XCTAssertGreaterThan(location.column, 0)
        }
    }
    // Original thirteen reader tests, preserving fixtures; numeric assertions use separate Decimal.
    func testReadCommaSeparatedCSVFile() throws {
        let result = try reader.read(fixture("comma-separated"), configuration: CSVConfiguration(quoting: .none))
        XCTAssertEqual(result.table.rows.map(\.count), [3,3,3])
        XCTAssertTrue(result.table.rows[2].allSatisfy { $0.decimal != nil })
        XCTAssertEqual(result.table.rows[2].map(\.literal), ["1.1","1.2","1.3"])
    }
    func testReadSemicolonSeparatedCSVFile() throws {
        let result = try reader.read(fixture("semicolon-separated"), configuration: CSVConfiguration(delimiter: ";", quoting: .none, decimalMark: .comma))
        XCTAssertEqual(result.table.rows.map(\.count), [3,3,3])
        XCTAssertTrue(result.table.rows[2].allSatisfy { $0.decimal != nil })
    }
    func testReadQuotedCommaSeparatedCSVFile() throws {
        let result = try reader.read(fixture("comma-separated-quote"), configuration: CSVConfiguration(decimalMark: .comma))
        XCTAssertEqual(result.table.rows.map(\.count), [3,3,3])
        XCTAssertTrue(result.table.rows.dropFirst().flatMap { $0 }.allSatisfy { $0.decimal != nil })
    }
    func testReadQuotedCSVFileWithQuoteEscape() throws {
        let result = try reader.read(fixture("quote-quote-escape"), configuration: CSVConfiguration())
        XCTAssertEqual(result.table.rows.map(\.count), [2,2])
        XCTAssertEqual(result.table.rows[0][0].literal, "test\" test")
        XCTAssertNotNil(result.table.rows[1][0].decimal); XCTAssertNil(result.table.rows[1][1].decimal)
    }
    func testReadQuotedCSVFileWithBackslashEscape() throws {
        let result = try reader.read(fixture("quote-backslash-escape"), configuration: CSVConfiguration(quoting: .character("\"", escaping: .backslash)))
        XCTAssertEqual(result.table.rows.map(\.count), [2,2])
        XCTAssertEqual(result.table.rows[0][0].literal, "test\" test")
        XCTAssertNotNil(result.table.rows[1][0].decimal); XCTAssertNil(result.table.rows[1][1].decimal)
    }
    func testReadCSVFileWithInvalidEncoding() throws {
        XCTAssertThrowsError(try reader.read(fixture("invalid-encoding"), configuration: CSVConfiguration())) {
            XCTAssertEqual($0 as? CSVError, .decodingFailed(.utf8))
        }
    }
    func testReadCSVFileWithMissingQuoteAtEnd() throws { try expectMalformed("missing-quote-atEnd") }
    func testReadCSVFileWithMissingBackslashBeforeValue() throws { try expectMalformed("missing-backslash-beforeValue", backslash: true) }
    func testReadCSVFileWithMissingBackslashAfterValue() throws { try expectMalformed("missing-backslash-afterValue", backslash: true) }
    func testReadCSVFileWithMissingValueForBackslashInquote() throws { try expectMalformed("missing-value-for-backslash-inquote", backslash: true) }
    func testReadCSVFileWithMissingValueForBackslash() throws { try expectMalformed("missing-value-for-backslash", backslash: true) }
    func testReadCSVFileWithQuoteInUnquotedValue() throws { try expectMalformed("quote-in-unquoted-value") }
    func testReadCSVFileWithBlankLines() throws {
        let result = try reader.read(fixture("blank-lines"), configuration: CSVConfiguration())
        XCTAssertEqual(result.table.rows.map { $0.map(\.literal) }, [["1"],["2"],[""],[""],["5"],["6"]])
    }

    func testNewlineEmptyAndRaggedSemantics() throws {
        XCTAssertEqual(try read("").table.rows, [])
        XCTAssertEqual(try read("\n").table.rows.map { $0.map(\.literal) }, [[""]])
        let result = try read("a,b,\r\n\r\nc\n\"d\r\ne\",f")
        XCTAssertEqual(result.table.rows.map { $0.map(\.literal) }, [["a","b",""],[""],["c"],["d\r\ne","f"]])
        XCTAssertEqual(result.serialization.lineEnding, .crlf)
        XCTAssertFalse(result.serialization.hasFinalLineEnding)
        XCTAssertTrue(try read("a\r").serialization.hasFinalLineEnding)
    }
    func testLiteralPrecisionAndExactDecimalInterpretation() throws {
        let huge = "12345678901234567890123456789012345678901234567890"
        let literals = ["00012", "001.2300", huge, "1e3", "-2.5E-2", "0.000", "1e1000000", "中文😀", " 1.2 "]
        let result = try read(literals.joined(separator: ","))
        XCTAssertEqual(result.table.rows[0].map(\.literal), literals)
        XCTAssertEqual(result.table.rows[0][0].decimal, Decimal(12))
        XCTAssertEqual(result.table.rows[0][1].decimal, Decimal(string: "1.23"))
        XCTAssertNil(result.table.rows[0][2].decimal)
        XCTAssertEqual(result.table.rows[0][3].decimal, Decimal(1000))
        XCTAssertEqual(result.table.rows[0][4].decimal, Decimal(string: "-0.025"))
        XCTAssertNil(result.table.rows[0][6].decimal)
        let output = try writer.write(result.table, configuration: result.configuration)
        XCTAssertEqual(try reader.read(output, configuration: result.configuration).table, result.table)
    }
    func testWriterPureRaggedPaddingAndDisplayOrder() throws {
        let table = CSVTable(rows: [[CSVCell(literal: "a"), CSVCell(literal: "b")], [CSVCell(literal: "c")]])
        let copy = table
        let options = CSVWriteOptions(columnOrder: [1,0])
        let data = try writer.write(table, configuration: CSVConfiguration(), options: options)
        XCTAssertEqual(table, copy)
        XCTAssertEqual(try read(String(decoding: data, as: UTF8.self)).table.rows.map { $0.map(\.literal) }, [["b","a"],["","c"]])
        for order in [[0,0], [0], [0,2], [-1,1]] {
            XCTAssertThrowsError(try writer.write(table, configuration: CSVConfiguration(), options: CSVWriteOptions(columnOrder: order))) {
                XCTAssertEqual($0 as? CSVError, .invalidColumnOrder)
            }
        }
    }
    func testWriterQuotingBackslashAndEmptyRoundTrips() throws {
        let table = CSVTable(rows: [[CSVCell(literal: "中文😀,\"\\\t\r\n")], [CSVCell(literal: "")]])
        for quoting: CSVQuoting in [.character("\"", escaping: .doubledQuote), .character("\"", escaping: .backslash), .character("'", escaping: .doubledQuote)] {
            let config = CSVConfiguration(quoting: quoting)
            for newline in [CSVLineEnding.lf, .crlf, .cr] {
                let options = CSVWriteOptions(serialization: CSVSerialization(lineEnding: newline, hasFinalLineEnding: true))
                let data = try writer.write(table, configuration: config, options: options)
                let result = try reader.read(data, configuration: config)
                XCTAssertEqual(result.table, table); XCTAssertEqual(result.serialization, options.serialization)
            }
        }
        XCTAssertEqual(try writer.write(CSVTable(), configuration: CSVConfiguration()), Data())
        XCTAssertThrowsError(try writer.write(CSVTable(rows: [[CSVCell(literal: "")]]), configuration: CSVConfiguration(quoting: .none)))
        XCTAssertThrowsError(try writer.write(table, configuration: CSVConfiguration(quoting: .none)))
    }
    func testExplicitConversionDoesNotReconstructNumber() throws {
        let source = "0001234567890123456789012345678901234567890.1200e+02"
        let table = CSVTable(rows: [[CSVCell(literal: source), CSVCell(literal: "hello.world")]])
        let config = CSVConfiguration(delimiter: ";", decimalMark: .comma)
        let preserve = try writer.write(table, configuration: config)
        XCTAssertEqual(try reader.read(preserve, configuration: config).table.rows[0][0].literal, source)
        let converted = try writer.write(table, configuration: config, options: CSVWriteOptions(literalPolicy: .convertDecimalMark(from: .point)))
        XCTAssertEqual(try reader.read(converted, configuration: config).table.rows[0].map(\.literal), [source.replacingOccurrences(of: ".", with: ","), "hello.world"])
        XCTAssertEqual(table.rows[0][0].literal, source)
    }
    func testAllEncodingCasesRoundTripOrFailExplicitly() throws {
        for encoding in CSVEncoding.allCases {
            let config = CSVConfiguration(encoding: encoding)
            let text: String
            switch encoding {
            case .gbk, .gb18030: text = "中文"
            case .japaneseEUC, .shiftJIS, .iso2022JP: text = "日本語"
            case .windows1251: text = "Привет"
            case .windows1253: text = "Αθήνα"
            case .windows1254: text = "Türkçe"
            case .windows1250, .isoLatin2: text = "Łódź"
            case .macRoman, .windows1252: text = "café"
            default: text = "中文😀"
            }
            let table = CSVTable(rows: [[CSVCell(literal: text)]])
            // All declared encodings are required to work on this macOS, not silently skip failures.
            let data = try writer.write(table, configuration: config)
            XCTAssertEqual(try reader.read(data, configuration: config).table, table, "\(encoding)")
        }
    }
    func testUnicodeBOMAndInvalidSequences() throws {
        for encoding: CSVEncoding in [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian] {
            let config = CSVConfiguration(encoding: encoding)
            let table = CSVTable(rows: [[CSVCell(literal: "中文😀")]])
            let options = CSVWriteOptions(serialization: CSVSerialization(hasByteOrderMark: true))
            let data = try writer.write(table, configuration: config, options: options)
            let result = try reader.read(data, configuration: config)
            XCTAssertEqual(result.table, table); XCTAssertTrue(result.serialization.hasByteOrderMark)
        }
        XCTAssertThrowsError(try reader.read(Data([0xff,0xfe,0x61]), configuration: CSVConfiguration(encoding: .utf16LittleEndian)))
        XCTAssertThrowsError(try reader.read(Data([0xef,0xbb,0xbf,0xff]), configuration: CSVConfiguration()))
        XCTAssertThrowsError(try reader.read(Data([0xff,0xfe,0x61,0]), configuration: CSVConfiguration()))
        XCTAssertThrowsError(try writer.write(CSVTable(), configuration: CSVConfiguration(encoding: .macRoman), options: CSVWriteOptions(serialization: CSVSerialization(hasByteOrderMark: true))))
    }
    func testUTF16BOMOverlapAndZeroFieldOutput() throws {
        let bytes = Data([0xff, 0xfe, 0, 0])
        let result = try reader.read(bytes, configuration: CSVConfiguration(encoding: .utf16LittleEndian))
        XCTAssertEqual(result.table.rows[0][0].literal, "\0")
        XCTAssertTrue(result.serialization.hasByteOrderMark)
        XCTAssertThrowsError(try writer.write(CSVTable(rows: [[]]), configuration: CSVConfiguration()))
    }
    func testOutputEncodingFailureHasLocationAndNoMutation() throws {
        let table = CSVTable(rows: [[CSVCell(literal: "😀")]])
        let copy = table
        XCTAssertThrowsError(try writer.write(table, configuration: CSVConfiguration(encoding: .windows1252))) {
            XCTAssertEqual($0 as? CSVError, .encodingFailed(.windows1252, row: 1, column: 1))
        }
        XCTAssertEqual(table, copy)
    }
    func testMalformedPhysicalLocationsAndEscapes() throws {
        XCTAssertThrowsError(try read("a,b\r\nc,ab\"d")) {
            guard case .malformedField(let location, _) = $0 as? CSVError else { return XCTFail("\($0)") }
            XCTAssertEqual(location, CSVSourceLocation(line: 2, column: 5))
        }
        try expectMalformed("tooMany-quotes-atEnd")
        XCTAssertThrowsError(try read("\"bad\\x\"", CSVConfiguration(quoting: .character("\"", escaping: .backslash))))
    }
    func testOriginalLargerFixtures() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        for (name, rows, columns, quoting) in [("test-doc-unquoted",987,12,CSVQuoting.none),("test-doc-quoted",1002,11,.character("\"", escaping: .doubledQuote))] {
            let bytes = try Data(contentsOf: root.appendingPathComponent("Table ToolTests/\(name).csv"))
            let parsed = try reader.read(bytes, configuration: CSVConfiguration(quoting: quoting))
            XCTAssertEqual(parsed.table.rows.count, rows)
            XCTAssertTrue(parsed.table.rows.allSatisfy { $0.count == columns })
        }
    }
}
