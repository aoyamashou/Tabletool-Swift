import Foundation
import CSVCore

/// Identity and display order belong to the document, never to transient table view indexes.
struct GridModel: Equatable {
    var table: CSVTable
    var rowIDs: [UUID]
    var columnIDs: [UUID]
    var columnOrder: [UUID]
    var configuration: CSVConfiguration
    var serialization: CSVSerialization

    init(table: CSVTable = CSVTable(rows: [Array(repeating: CSVCell(literal: ""), count: 3)]),
         configuration: CSVConfiguration = CSVConfiguration(),
         serialization: CSVSerialization = CSVSerialization()) {
        self.table = table
        rowIDs = table.rows.map { _ in UUID() }
        columnIDs = (0..<table.columnCount).map { _ in UUID() }
        columnOrder = columnIDs
        self.configuration = configuration
        self.serialization = serialization
    }
    var headerOffset: Int { configuration.firstRowAsHeader && !table.rows.isEmpty ? 1 : 0 }
    var visibleRowCount: Int { table.rows.count - headerOffset }
    var outputTable: CSVTable {
        CSVTable(rows: table.rows.map { row in
            row + Array(repeating: CSVCell(literal: ""), count: max(0, columnIDs.count - row.count))
        })
    }
    var storageColumnOrder: [Int] { columnOrder.compactMap { columnIDs.firstIndex(of: $0) } }
    func literal(row: Int, column: Int) -> String {
        let r = row + headerOffset
        guard table.rows.indices.contains(r), storageColumnOrder.indices.contains(column) else { return "" }
        let c = storageColumnOrder[column]
        return table.rows[r].indices.contains(c) ? table.rows[r][c].literal : ""
    }
    func title(column: Int) -> String {
        guard configuration.firstRowAsHeader, !table.rows.isEmpty else { return String(column + 1) }
        let c = storageColumnOrder[column]
        return table.rows[0].indices.contains(c) ? table.rows[0][c].literal : ""
    }
    mutating func edit(row: Int, column: Int, literal: String) {
        let r = row + headerOffset
        guard table.rows.indices.contains(r), storageColumnOrder.indices.contains(column) else { return }
        let c = storageColumnOrder[column]
        while table.rows[r].count <= c { table.rows[r].append(CSVCell(literal: "")) }
        table.rows[r][c] = CSVCell(literal: literal)
    }
    mutating func insertRows(at index: Int, values: [[String]]? = nil) {
        let destination = min(max(0, index), visibleRowCount) + headerOffset
        let data = values ?? [Array(repeating: "", count: columnIDs.count)]
        let width = data.map(\.count).max() ?? 0
        while columnIDs.count < width { insertColumn(at: columnOrder.count) }
        for (offset, fields) in data.enumerated() {
            var cells = Array(repeating: CSVCell(literal: ""), count: columnIDs.count)
            for (displayColumn, value) in fields.enumerated() {
                cells[storageColumnOrder[displayColumn]] = CSVCell(literal: value)
            }
            table.rows.insert(cells, at: destination + offset)
            rowIDs.insert(UUID(), at: destination + offset)
        }
    }
    mutating func deleteRows(_ indexes: IndexSet) {
        for row in indexes.sorted(by: >) where row >= 0 && row < visibleRowCount {
            table.rows.remove(at: row + headerOffset); rowIDs.remove(at: row + headerOffset)
        }
    }
    mutating func insertColumn(at index: Int) {
        let id = UUID()
        // Materialize missing fields only when the user explicitly changes the grid structure.
        for r in table.rows.indices {
            while table.rows[r].count < columnIDs.count { table.rows[r].append(CSVCell(literal: "")) }
            table.rows[r].append(CSVCell(literal: ""))
        }
        columnIDs.append(id)
        columnOrder.insert(id, at: min(max(0, index), columnOrder.count))
    }
    mutating func deleteColumns(_ indexes: IndexSet) {
        let ids = indexes.compactMap { columnOrder.indices.contains($0) ? columnOrder[$0] : nil }
        let storage = ids.compactMap { columnIDs.firstIndex(of: $0) }.sorted(by: >)
        for c in storage {
            for r in table.rows.indices where table.rows[r].indices.contains(c) { table.rows[r].remove(at: c) }
            columnIDs.remove(at: c)
        }
        columnOrder.removeAll { ids.contains($0) }
    }
    mutating func moveColumn(from: Int, to: Int) {
        guard columnOrder.indices.contains(from), columnOrder.indices.contains(to) else { return }
        columnOrder.insert(columnOrder.remove(at: from), at: to)
    }
    mutating func moveRows(_ indexes: IndexSet, to: Int) {
        let valid = indexes.filter { $0 >= 0 && $0 < visibleRowCount }
        let rows = valid.map { table.rows[$0 + headerOffset] }
        let ids = valid.map { rowIDs[$0 + headerOffset] }
        let destination = min(max(0, to), visibleRowCount) - valid.filter { $0 < to }.count + headerOffset
        deleteRows(IndexSet(valid))
        table.rows.insert(contentsOf: rows, at: destination)
        rowIDs.insert(contentsOf: ids, at: destination)
    }
    func selectedTable(rows: IndexSet, columns: IndexSet) -> CSVTable {
        let selectedColumns = columns.isEmpty ? Array(columnOrder.indices) : Array(columns)
        let selectedRows = rows.isEmpty ? Array(0..<visibleRowCount) : Array(rows)
        return CSVTable(rows: selectedRows.map { r in selectedColumns.map { c in CSVCell(literal: literal(row: r, column: c)) } })
    }
}

/// Saving can clear NSDocument's edited flag before its input-byte snapshot is refreshed.
/// A separate conservative guard prevents reinterpreting stale bytes in that interval.
enum SourceReinterpretationPolicy {
    static func allows(hasSource: Bool, hasEditedSource: Bool, isDocumentEdited: Bool) -> Bool {
        !hasSource || (!hasEditedSource && !isDocumentEdited)
    }
}
