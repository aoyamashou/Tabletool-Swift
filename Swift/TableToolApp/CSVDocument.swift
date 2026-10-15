import AppKit
import CSVCore

@objc(CSVDocument)
final class CSVDocument: NSDocument {
    var model = GridModel()
    private(set) var sourceData: Data?
    private(set) var hasEditedSource = false
    private var preparedWriteData: Data?
    private var detectionNotice = ""
    private var gridController: GridViewController?
    var configuration: CSVConfiguration { get { model.configuration } set { model.configuration = newValue } }
    var serialization: CSVSerialization { get { model.serialization } set { model.serialization = newValue } }
    var table: CSVTable { get { model.table } set { model = GridModel(table: newValue, configuration: configuration, serialization: serialization) } }

    override init() {
        super.init()
        // Use the documented setter so NSDocument observes UndoManager notifications.
        undoManager = UndoManager()
    }
    override class var autosavesInPlace: Bool { true }
    // read(from:ofType:) is a synchronous, nonisolated AppKit override. Keep
    // document reads on AppKit's main thread so its UI commit is synchronous.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override func makeWindowControllers() {
        let controller = GridViewController(document: self)
        controller.detectionNotice = detectionNotice
        gridController = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.toolbar = controller.makeToolbar()
        window.toolbarStyle = .expanded
        window.setContentSize(NSSize(width: 1080, height: 650))
        window.contentMinSize = NSSize(width: 720, height: 420)
        window.center()
        addWindowController(NSWindowController(window: window))
    }
    @discardableResult func commitPendingEditing() -> Bool {
        guard let window = gridController?.view.window else { return true }
        return window.makeFirstResponder(gridController?.tableView)
    }
    func applyChange(_ title: String, _ change: (inout GridModel) -> Void) {
        let before = model
        change(&model)
        guard before != model else { return }
        hasEditedSource = true
        undoManager?.registerUndo(withTarget: self) { document in document.restore(before, title: title) }
        undoManager?.setActionName(title)
        gridController?.reload()
    }
    private func restore(_ snapshot: GridModel, title: String) {
        let previous = model
        undoManager?.registerUndo(withTarget: self) { document in document.restore(previous, title: title) }
        undoManager?.setActionName(title)
        model = snapshot
        hasEditedSource = true
        gridController?.reload()
    }
    func reinterpret(_ config: CSVConfiguration) throws {
        guard commitPendingEditing() else { return }
        guard SourceReinterpretationPolicy.allows(hasSource: sourceData != nil, hasEditedSource: hasEditedSource, isDocumentEdited: isDocumentEdited) else { throw CSVError.invalidConfiguration("输入原字节已有编辑；请保存并重新打开文件后更改输入格式。") }
        try config.validate()
        if let sourceData {
            let result = try CSVReader().read(sourceData, configuration: config)
            model = GridModel(table: result.table, configuration: result.configuration, serialization: result.serialization)
            undoManager?.removeAllActions()
            gridController?.reload()
        } else {
            applyChange("输入格式") { $0.configuration = config }
        }
    }
    override func read(from data: Data, ofType typeName: String) throws {
        let detection = try CSVDetector().detect(data, encodings: CSVEncoding.allCases)
        guard let candidate = detection.candidates.first else { throw CSVError.invalidConfiguration("无法识别文件编码或CSV格式。") }
        let result = try detection.readResult(for: candidate.configuration)
            ?? CSVReader().read(data, configuration: candidate.configuration)
        model = GridModel(table: result.table, configuration: result.configuration, serialization: result.serialization)
        sourceData = data
        hasEditedSource = false
        undoManager?.removeAllActions()
        detectionNotice = detection.isAmbiguous ? "检测存在歧义，请确认输入格式；可在未编辑时更正。" : ""
        MainActor.assumeIsolated {
            gridController?.detectionNotice = detectionNotice
            gridController?.reload()
        }
    }
    override func data(ofType typeName: String) throws -> Data {
        if let preparedWriteData { return preparedWriteData }
        guard commitPendingEditing() else { throw CSVError.invalidConfiguration("请完成当前单元格编辑。") }
        return try CSVWriter().write(model.outputTable, configuration: configuration,
                                     options: CSVWriteOptions(serialization: serialization, columnOrder: model.table.rows.isEmpty ? nil : model.storageColumnOrder))
    }
    override func save(to url: URL, ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard commitPendingEditing() else {
            completionHandler(CSVError.invalidConfiguration("请完成当前单元格编辑。")); return
        }
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool { false }

    override func writeSafely(to url: URL, ofType typeName: String,
                              for saveOperation: NSDocument.SaveOperationType) throws {
        guard Thread.isMainThread else { throw CSVError.invalidConfiguration("保存必须在文档主线程执行。") }
        try MainActor.assumeIsolated {
            // Encode before NSDocument creates temporary files or moves the old version.
            let bytes = try data(ofType: typeName)
            try CSVFileSafety.validateDestination(url)
            preparedWriteData = bytes
            defer { preparedWriteData = nil }
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
            if saveOperation != .saveToOperation && saveOperation != .autosaveElsewhereOperation {
                sourceData = bytes
                hasEditedSource = false
                // Storage IDs/order and Undo history stay stable. The refreshed bytes are already
                // in display order; a subsequent explicit reinterpretation rebuilds the model.
            }
        }
    }

    /// nil is an explicit cancelled panel result: no encoding or filesystem access.
    @discardableResult
    func exportConverted(to destination: URL?, configuration target: CSVConfiguration,
                         serialization targetSerialization: CSVSerialization? = nil) throws -> Bool {
        guard let destination else { return false }
        if let fileURL, destination.resolvingSymlinksInPath().standardizedFileURL == fileURL.resolvingSymlinksInPath().standardizedFileURL {
            throw CSVError.invalidConfiguration("格式转换请选择其他文件，以保留当前文档。")
        }
        guard commitPendingEditing() else { throw CSVError.invalidConfiguration("请完成当前单元格编辑。") }
        let options = CSVWriteOptions(serialization: targetSerialization ?? serialization,
                                      columnOrder: model.table.rows.isEmpty ? nil : model.storageColumnOrder,
                                      literalPolicy: .convertDecimalMark(from: configuration.decimalMark))
        let bytes = try CSVWriter().write(model.outputTable, configuration: target, options: options)
        try CSVFileSafety.export(bytes, to: destination)
        return true
    }

}
