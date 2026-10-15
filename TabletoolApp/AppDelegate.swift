import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSDocumentController.shared
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let child = NSMenu(title: title); item.submenu = child; menu.addItem(item)
            return child
        }
        let app = submenu("Tabletool Swift")
        app.addItem(withTitle: "关于 Tabletool Swift", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "退出 Tabletool Swift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("文件")
        file.addItem(withTitle: "新建", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "打开…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "最近打开")
        let recentItem = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: ""); recentItem.submenu = recent
        file.addItem(recentItem)
        recent.delegate = self

        file.addItem(.separator())
        file.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "保存", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "另存为…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "转换格式并导出副本…", action: #selector(CSVDocument.convertFormat(_:)), keyEquivalent: "")
        file.addItem(withTitle: "恢复为已保存版本…", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        let edit = submenu("编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "复制", action: #selector(GridViewController.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(GridViewController.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")
        let grid = submenu("表格")
        grid.addItem(withTitle: "在选中位置插入行", action: #selector(GridViewController.insertRow(_:)), keyEquivalent: "")
        grid.addItem(withTitle: "删除选中行", action: #selector(GridViewController.deleteRows(_:)), keyEquivalent: "")
        grid.addItem(withTitle: "在选中位置插入列", action: #selector(GridViewController.insertColumn(_:)), keyEquivalent: "")
        grid.addItem(withTitle: "删除选中列", action: #selector(GridViewController.deleteColumns(_:)), keyEquivalent: "")
        grid.addItem(withTitle: "编辑选中列表头…", action: #selector(GridViewController.editHeader(_:)), keyEquivalent: "")
        let window = submenu("窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "前置所有窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApplication.shared.windowsMenu = window
        NSApplication.shared.mainMenu = menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "最近打开" else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "清除菜单", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSDocumentController.shared.presentError(error) }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}
