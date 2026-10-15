import Foundation
import CSVCore

var failures = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    if value() { print("PASS \(name)") } else { print("FAIL \(name)"); failures += 1 }
}
var model = GridModel()
check(model.visibleRowCount == 1 && model.columnIDs.count == 3, "new 3x1")
let original = model
model.edit(row: 0, column: 0, literal: "001234567890123456789012345678901234567890")
check(model.literal(row: 0, column: 0) == "001234567890123456789012345678901234567890", "literal precision")
let edited = model
model = original
check(model == original, "snapshot undo includes identities")
model = edited
check(model == edited, "snapshot redo")
model.insertRows(at: 0, values: [["h1", "h2", "h3"], ["甲", "乙", "丙"], ["a", "b", "c"]])
model.configuration.firstRowAsHeader = true
let headerID = model.rowIDs[0]
let rowID = model.rowIDs[1]
model.moveRows(IndexSet([0, 2]), to: 3)
check(model.rowIDs[0] == headerID && model.rowIDs[2] == rowID, "noncontiguous row move preserves header/IDs")
let columnID = model.columnOrder[0]
model.moveColumn(from: 0, to: 2)
check(model.columnOrder[2] == columnID && model.title(column: 2) == "h1", "column/header move")
model.insertRows(at: 0, values: [["first", "second", "third", "extra"]])
check(model.literal(row: 0, column: 0) == "first" && model.literal(row: 0, column: 2) == "third" && model.columnIDs.count == 4, "paste display order and expansion")
model.deleteColumns(IndexSet([0, 2]))
check(model.columnIDs.count == 2 && model.columnOrder.count == 2 && model.literal(row: 0, column: 0) == "second", "noncontiguous column deletion")
model.deleteRows(IndexSet(0..<model.visibleRowCount))
check(model.visibleRowCount == 0 && model.rowIDs == [headerID], "delete all keeps header")
model.insertRows(at: 0)
check(model.visibleRowCount == 1, "insert after empty")
model.deleteColumns(IndexSet(model.columnOrder.indices))
model.insertColumn(at: 0)
check(model.columnOrder.count == 1 && model.table.rows.allSatisfy { $0.count == 1 }, "insert column after empty")
let ragged = GridModel(table: CSVTable(rows: [[CSVCell(literal: "a"), CSVCell(literal: "b")], []]))
check(ragged.table.rows[1].isEmpty && ragged.outputTable.rows[1].count == 2, "ragged storage preserved until output")
let exchange = GridModel(table: CSVTable(rows: [[CSVCell(literal: "a\tb"), CSVCell(literal: "line\nbreak")]]))
check(exchange.selectedTable(rows: [0], columns: [1]).rows[0][0].literal == "line\nbreak", "selection retains literal newlines")
check(SourceReinterpretationPolicy.allows(hasSource: true, hasEditedSource: false, isDocumentEdited: false), "clean source may reinterpret")
check(!SourceReinterpretationPolicy.allows(hasSource: true, hasEditedSource: true, isDocumentEdited: false), "save-cleared dirty flag cannot expose stale source")
check(!SourceReinterpretationPolicy.allows(hasSource: true, hasEditedSource: false, isDocumentEdited: true), "pending edits block reinterpret")
check(SourceReinterpretationPolicy.allows(hasSource: false, hasEditedSource: true, isDocumentEdited: true), "new document format does not re-read bytes")
if failures > 0 { exit(1) }
print("grid_model=pass")
