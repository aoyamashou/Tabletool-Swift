import XCTest
import CSVCore

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
}
