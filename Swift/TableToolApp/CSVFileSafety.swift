import Foundation

/// Validate before creating any output. NSDocument still owns normal safe-save/versions.
enum CSVFileSafety {
    static func validateDestination(_ url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        var directory: ObjCBool = false
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path, isDirectory: &directory)
        if exists {
            guard !directory.boolValue else { throw CocoaError(.fileWriteInvalidFileName) }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
            guard mode & 0o222 != 0, manager.isWritableFile(atPath: url.path) else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let parent = url.deletingLastPathComponent()
        // A save-panel sandbox grant may allow the selected file without granting a
        // writable-directory access() result. Inspect POSIX metadata when available;
        // let the coordinated/atomic write enforce the actual sandbox permission.
        if let attributes = try? manager.attributesOfItem(atPath: parent.path),
           let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue, mode & 0o222 == 0 {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    static func export(_ data: Data, to url: URL) throws {
        try validateDestination(url)
        try data.write(to: url, options: .atomic)
    }
}
