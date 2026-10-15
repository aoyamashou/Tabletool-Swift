import Foundation
import CSVCore

@main
struct CoreReadProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let configuration = CSVConfiguration(quoting: .none)
        let parsed = try CSVReader().read(data, configuration: configuration)
        guard parsed.table.rows.count == 3, parsed.table.columnCount == 3,
              parsed.table.rows[2].map(\.literal) == ["1.1", "1.2", "1.3"] else { exit(1) }
        let encoded = try CSVWriter().write(parsed.table, configuration: configuration)
        guard try CSVReader().read(encoded, configuration: configuration).table == parsed.table else { exit(1) }
        print("Swift CSVCore实际读取及内存写出重读通过，rows=3，columns=3")
    }
}
