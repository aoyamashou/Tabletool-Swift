import Foundation

/// English text is the lookup key and the fallback; translations live in <lang>.lproj/Localizable.strings.
func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
