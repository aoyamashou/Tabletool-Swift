import XCTest
@testable import CSVCore

final class ContractTests: XCTestCase {
    func testLiteralIsIndependentOfNumericInterpretation() throws {
        let leading = CSVCell(literal: "001.2300", decimal: Decimal(string: "1.23"))
        let huge = CSVCell(literal: "12345678901234567890123456789012345678901234567890")
        let table = CSVTable(rows: [[leading, huge, CSVCell(literal: "中文😀")], [CSVCell(literal: "")]])
        XCTAssertEqual(table.rows[0][0].literal, "001.2300")
        XCTAssertEqual(table.rows[0][1].literal, huge.literal)
        XCTAssertNil(huge.decimal)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows[1].count, 1)
        XCTAssertEqual(CSVWriteOptions().literalPolicy, .preserve)
    }

    func testConfigurationRejectsAmbiguousSyntax() throws {
        try CSVConfiguration().validate()
        try CSVConfiguration(delimiter: "\t", quoting: .none).validate()
        XCTAssertThrowsError(try CSVConfiguration(delimiter: "\n").validate())
        XCTAssertThrowsError(try CSVConfiguration(delimiter: "\"").validate())
        XCTAssertThrowsError(try CSVConfiguration(delimiter: "\\", quoting: .character("\"", escaping: .backslash)).validate())
    }

    func testPublicInterfacesCanBeConsumedWithoutImplementation() throws {
        struct Reader: CSVReading {
            func read(_ data: Data, configuration: CSVConfiguration) throws -> CSVReadResult {
                CSVReadResult(table: CSVTable(), configuration: configuration, serialization: CSVSerialization())
            }
        }
        struct Writer: CSVWriting {
            func write(_ table: CSVTable, configuration: CSVConfiguration, options: CSVWriteOptions) throws -> Data { Data() }
        }
        struct Detector: CSVDetecting {
            func detect(_ data: Data, encodings: [CSVEncoding]) throws -> CSVDetectionResult {
                CSVDetectionResult(candidates: [], isAmbiguous: true)
            }
        }
        let reader: any CSVReading = Reader()
        let writer: any CSVWriting = Writer()
        let detector: any CSVDetecting = Detector()
        let parsed = try reader.read(Data(), configuration: CSVConfiguration())
        XCTAssertTrue(try writer.write(parsed.table, configuration: parsed.configuration, options: CSVWriteOptions()).isEmpty)
        XCTAssertTrue(try detector.detect(Data(), encodings: [.utf8]).candidates.isEmpty)
    }

    // MARK: Localization

    private func strings(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(CSVError.resourceBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language), language)
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testEveryLanguageTranslatesTheSameMessages() throws {
        let english = try strings("en")
        XCTAssertFalse(english.isEmpty)
        for language in ["ja", "zh-Hans"] {
            let table = try strings(language)
            XCTAssertEqual(Set(table.keys), Set(english.keys), "\(language) keys differ from en")
            // Every message needs a real translation, and keeps the same format placeholders.
            for (key, value) in table {
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
                XCTAssertEqual(value.components(separatedBy: "%").count, key.components(separatedBy: "%").count,
                               "\(language) placeholders differ: \(key)")
            }
        }
    }

    func testErrorMessagesAreTranslatedPerLanguage() throws {
        // The test host's own language decides CSVError.errorDescription, so check each language's table directly.
        let expected = ["en": "Unclosed quoted field", "ja": "引用符が閉じられていません", "zh-Hans": "引号未闭合"]
        for (language, text) in expected {
            // Find the language's table the same way the system does, then open its .lproj folder.
            let table = try XCTUnwrap(CSVError.resourceBundle.path(forResource: "Localizable", ofType: "strings",
                                                                  inDirectory: nil, forLocalization: language), language)
            let bundle = try XCTUnwrap(Bundle(path: URL(fileURLWithPath: table).deletingLastPathComponent().path), language)
            XCTAssertEqual(bundle.localizedString(forKey: "Unclosed quoted field", value: nil, table: nil), text)
        }
        XCTAssertNotNil(CSVError.invalidColumnOrder.errorDescription)
    }
}
