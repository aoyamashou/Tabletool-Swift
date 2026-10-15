import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var recentMenu: NSMenu?
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSDocumentController.shared
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let child = NSMenu(title: title); item.submenu = child; menu.addItem(item)
            return child
        }
        let appName = "Tabletool Swift"
        let app = submenu(appName)
        app.addItem(withTitle: tr("About %@", appName), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: tr("Quit %@", appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu(tr("File"))
        file.addItem(withTitle: tr("New"), action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: tr("Open…"), action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: tr("Open Recent"))
        let recentItem = NSMenuItem(title: tr("Open Recent"), action: nil, keyEquivalent: ""); recentItem.submenu = recent
        file.addItem(recentItem)
        recent.delegate = self
        recentMenu = recent

        file.addItem(.separator())
        file.addItem(withTitle: tr("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: tr("Save"), action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: tr("Save As…"), action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: tr("Convert Format and Export Copy…"), action: #selector(CSVDocument.convertFormat(_:)), keyEquivalent: "")
        file.addItem(withTitle: tr("Revert to Saved…"), action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        let edit = submenu(tr("Edit"))
        edit.addItem(withTitle: tr("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: tr("Redo"), action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Copy"), action: #selector(GridViewController.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Paste"), action: #selector(GridViewController.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        let grid = submenu(tr("Table"))
        grid.addItem(withTitle: tr("Insert Row at Selection"), action: #selector(GridViewController.insertRow(_:)), keyEquivalent: "")
        grid.addItem(withTitle: tr("Delete Selected Rows"), action: #selector(GridViewController.deleteRows(_:)), keyEquivalent: "")
        grid.addItem(withTitle: tr("Insert Column at Selection"), action: #selector(GridViewController.insertColumn(_:)), keyEquivalent: "")
        grid.addItem(withTitle: tr("Delete Selected Columns"), action: #selector(GridViewController.deleteColumns(_:)), keyEquivalent: "")
        grid.addItem(withTitle: tr("Edit Selected Column Header…"), action: #selector(GridViewController.editHeader(_:)), keyEquivalent: "")
        let window = submenu(tr("Window"))
        window.addItem(withTitle: tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: tr("Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApplication.shared.windowsMenu = window
        NSApplication.shared.mainMenu = menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Clear Menu"), action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSDocumentController.shared.presentError(error) }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}
