import AppKit
import CSVCore

@main
struct DocumentProbe {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        var failures = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if value() { print("PASS \(name)") } else { print("FAIL \(name)"); failures += 1 }
        }
        let document = CSVDocument()
        let other = CSVDocument()
        NSDocumentController.shared.addDocument(document)
        NSDocumentController.shared.addDocument(other)
        check(document.model.visibleRowCount == 1 && document.model.columnIDs.count == 3, "NSDocument default 3x1")
        let input = Data("name,value\nAda,0012".utf8)
        try document.read(from: input, ofType: "CSV Document")
        let before = document.model
        guard let undo = document.undoManager else { print("FAIL UndoManager missing"); exit(1) }
        document.applyChange("Edit") { $0.edit(row: 0, column: 1, literal: "00012345678901234567890123456789012345678901234567890") }
        // Match a real AppKit event: its automatic undo group closes on the next run-loop turn.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let after = document.model
        check(after != before && document.isDocumentEdited, "edit marks document dirty")
        check(other.model.visibleRowCount == 1 && other.table.rows[0][1].literal == "", "document state isolated")
        undo.undo()
        check(document.model == before, "real UndoManager restores complete model")
        check(!document.isDocumentEdited, "undo to saved state clears dirty count")
        undo.redo()
        check(document.model == after, "real UndoManager redo")
        check(document.isDocumentEdited, "redo restores dirty count")
        let serialized = try document.data(ofType: "CSV Document")
        let parsed = try CSVReader().read(serialized, configuration: document.configuration)
        check(parsed.table.rows == after.outputTable.rows, "document encoding preserves literals")
        document.updateChangeCount(.changeCleared)
        do { try document.reinterpret(CSVConfiguration()); check(false, "stale source rejected after dirty cleared") }
        catch { check(document.model == after, "stale source rejection preserves edited model") }
        try document.read(from: input, ofType: "CSV Document")
        let clean = document.model
        var invalid = document.configuration; invalid.delimiter = "\n"
        do { try document.reinterpret(invalid); check(false, "invalid input format rejected") }
        catch { check(document.model == clean && document.sourceData == input, "format failure preserves model and original bytes") }
        do {
            try document.read(from: URL(fileURLWithPath: "/nonexistent/tabletool-document-probe.csv"), ofType: "CSV Document")
            check(false, "missing file rejected")
        } catch { check(true, "missing file rejected") }
        document.close(); other.close()
        if failures > 0 { exit(1) }
        print("document_probe=pass; GUI panels and lifecycle prompts remain M2")
    }
}
