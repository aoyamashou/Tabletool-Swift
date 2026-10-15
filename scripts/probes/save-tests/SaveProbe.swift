import AppKit
import CSVCore

@main
struct SaveProbe {
    @MainActor
    static func main() {
        do { try run() }
        catch { print("FAIL save probe unexpected error: \(error)"); exit(1) }
    }
    @MainActor
    static func run() throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var failures = 0
        func check(_ value: @autoclosure () throws -> Bool, _ name: String) rethrows {
            if try value() { print("PASS \(name)") } else { print("FAIL \(name)"); failures += 1 }
        }
        func save(_ document: CSVDocument, to url: URL, operation: NSDocument.SaveOperationType) throws {
            // End the preceding edit event before simulating a separate Save/Save As action.
            // AppKit owns automatic Undo grouping; manually closing its group is invalid.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            var result: Result<Void, Error>?
            document.save(to: url, ofType: "CSV Document", for: operation) { error in
                result = error.map { .failure($0) } ?? .success(())
            }
            let timeout = Date(timeIntervalSinceNow: 10)
            while result == nil && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
            guard let result else { throw CSVError.invalidConfiguration("NSDocument save completion timed out") }
            try result.get()
        }
        func expectedRows(_ model: GridModel) -> [[String]] {
            model.outputTable.rows.map { row in model.storageColumnOrder.map { row[$0].literal } }
        }
        let originalURL = root.appendingPathComponent("original.csv")
        let originalBytes = Data("name,amount\nAda,000123456789012345678901234567890.1200".utf8)
        try originalBytes.write(to: originalURL)
        let document = CSVDocument()
        NSDocumentController.shared.addDocument(document)
        try document.read(from: originalBytes, ofType: "CSV Document")
        document.fileURL = originalURL; document.fileType = "CSV Document"
        document.applyChange("Edit and reorder") { model in
            model.edit(row: 0, column: 0, literal: "小明😀")
            model.moveColumn(from: 0, to: 1)
        }
        let expected = expectedRows(document.model)
        let stableIDs = document.model.columnOrder
        try save(document, to: originalURL, operation: .saveOperation)
        let saved = try Data(contentsOf: originalURL)
        check(saved == document.sourceData && !document.hasEditedSource, "save refreshes exact input byte snapshot")
        check(document.model.columnOrder == stableIDs, "save preserves stable column IDs and undo mapping")
        check(document.fileURL == originalURL, "save keeps current URL")
        check(!document.isDocumentEdited, "saved edits are clean before reinterpretation")
        let parsed = try CSVReader().read(saved, configuration: document.configuration)
        check(parsed.table.rows.map { $0.map(\.literal) } == expected, "saved header literals and display order round trip")
        try document.reinterpret(document.configuration)
        check(document.table.rows.map { $0.map(\.literal) } == expected, "reparse uses newly saved display order rather than old bytes")

        let secondURL = root.appendingPathComponent("save-as.csv")
        document.applyChange("Edit for save-as") { $0.edit(row: 0, column: 1, literal: "Other😀") }
        try save(document, to: secondURL, operation: .saveAsOperation)
        try check(document.fileURL == secondURL && document.sourceData == Data(contentsOf: secondURL), "save-as switches URL and refreshes snapshot")
        try check(Data(contentsOf: originalURL) == saved, "save-as keeps previous file intact")
        let beforeModel = document.model
        let beforeSource = document.sourceData
        let beforeURL = document.fileURL
        let beforeConfig = document.configuration
        let convertedURL = root.appendingPathComponent("converted.csv")
        var target = document.configuration
        target.delimiter = ";"; target.decimalMark = .comma; target.encoding = .utf16LittleEndian
        let outputSerialization = CSVSerialization(lineEnding: .crlf, hasFinalLineEnding: true, hasByteOrderMark: true)
        try document.exportConverted(to: convertedURL, configuration: target, serialization: outputSerialization)
        let converted = try CSVReader().read(Data(contentsOf: convertedURL), configuration: target)
        check(converted.configuration == target && converted.serialization == outputSerialization, "conversion preserves chosen encoding and serialization")
        check(converted.table.rows[1][0].literal == "000123456789012345678901234567890,1200", "conversion preserves huge numeric literal precision and leading zeros")
        check(document.model == beforeModel && document.sourceData == beforeSource && document.fileURL == beforeURL && document.configuration == beforeConfig,
              "conversion keeps current model URL configuration and source unchanged")
        let filesBeforeCancel = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        try check(!document.exportConverted(to: nil, configuration: target), "cancel returns without writing")
        try check(FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == filesBeforeCancel, "cancel leaves file set unchanged")
        do { try document.exportConverted(to: secondURL, configuration: target); check(false, "conversion cannot replace active file") }
        catch { try check(Data(contentsOf: secondURL) == beforeSource, "conversion cannot replace active file") }

        var unrepresentable = target; unrepresentable.encoding = .windows1252
        let protectedURL = root.appendingPathComponent("protected.csv")
        let sentinel = Data("DO NOT CHANGE".utf8)
        try sentinel.write(to: protectedURL)
        do { try document.exportConverted(to: protectedURL, configuration: unrepresentable); check(false, "conversion encoding failure") }
        catch { try check(Data(contentsOf: protectedURL) == sentinel && document.sourceData == beforeSource, "conversion encoding failure preserves original bytes and input snapshot") }
        document.applyChange("Unrepresentable encoding") { $0.configuration.encoding = .windows1252 }
        do { try document.writeSafely(to: secondURL, ofType: "CSV Document", for: .saveOperation); check(false, "save encoding failure") }
        catch { try check(Data(contentsOf: secondURL) == beforeSource && document.sourceData == beforeSource, "save encoding failure preserves file and snapshot") }
        document.model = beforeModel

        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: protectedURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: protectedURL.path) }
        do { try document.writeSafely(to: protectedURL, ofType: "CSV Document", for: .saveAsOperation); check(false, "read-only path rejected") }
        catch { try check(Data(contentsOf: protectedURL) == sentinel && document.fileURL == beforeURL, "read-only path rejected without file or URL mutation") }
        let noWriteDirectory = root.appendingPathComponent("read-only-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: noWriteDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: noWriteDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: noWriteDirectory.path) }
        let blockedURL = noWriteDirectory.appendingPathComponent("new.csv")
        do { try document.exportConverted(to: blockedURL, configuration: target); check(false, "read-only directory rejected") }
        catch { check(!FileManager.default.fileExists(atPath: blockedURL.path), "read-only directory rejected without partial file") }

        let malformedURL = root.appendingPathComponent("manual-format.csv")
        let malformedBytes = Data("a,b\n1,ab\"broken".utf8)
        try malformedBytes.write(to: malformedURL)
        let formatDocument = CSVDocument()
        NSDocumentController.shared.addDocument(formatDocument)
        try formatDocument.read(from: malformedBytes, ofType: "CSV Document")
        let beforeFormatFailure = formatDocument.model
        do { try formatDocument.reinterpret(CSVConfiguration()); check(false, "parse failure preserves file") }
        catch { try check(Data(contentsOf: malformedURL) == malformedBytes && formatDocument.model == beforeFormatFailure, "parse failure preserves file and current model") }
        document.updateChangeCount(.changeCleared); formatDocument.updateChangeCount(.changeCleared)
        document.close(); formatDocument.close()
        if failures > 0 { exit(1) }
        print("save_probe=pass; system panel cancellation and lifecycle UI remain M2")
    }
}
