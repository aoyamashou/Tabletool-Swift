import Foundation

/// ASCII numeric syntax and exact Decimal interpretation. Literal storage never depends on this.
enum CSVNumber {
    static func normalized(_ literal: String, mark: CSVDecimalMark) -> String? {
        let text = mark == .comma ? literal.replacingOccurrences(of: ",", with: ".") : literal
        let pattern = "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return text
    }

    /// A string coefficient plus base-ten exponent allows comparison beyond Decimal precision.
    private static func canonical(_ text: String) -> String? {
        var input = text.lowercased()
        let negative = input.hasPrefix("-")
        if input.hasPrefix("+") || negative { input.removeFirst() }
        let parts = input.split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let exponent: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), absBounded(parsed) else { return nil }
            exponent = parsed
        } else { exponent = 0 }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard mantissa.count <= 2 else { return nil }
        let fractionCount = mantissa.count == 2 ? mantissa[1].count : 0
        var digits = mantissa.joined()
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0" }
        var scale = exponent - fractionCount
        while digits.last == "0" { digits.removeLast(); scale += 1 }
        return "\(negative ? "-" : "")\(digits)e\(scale)"
    }

    private static func absBounded(_ value: Int) -> Bool { value >= -1_000_000 && value <= 1_000_000 }

    static func decimal(_ literal: String, mark: CSVDecimalMark) -> Decimal? {
        guard let text = normalized(literal, mark: mark), let expected = canonical(text),
              var value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
              canonical(NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))) == expected else { return nil }
        return value
    }

    static func convert(_ literal: String, from: CSVDecimalMark, to: CSVDecimalMark) -> String {
        guard from != to, normalized(literal, mark: from) != nil else { return literal }
        return literal.replacingOccurrences(of: from.rawValue, with: to.rawValue)
    }
}
