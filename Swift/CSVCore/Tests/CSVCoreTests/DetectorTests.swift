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
}
