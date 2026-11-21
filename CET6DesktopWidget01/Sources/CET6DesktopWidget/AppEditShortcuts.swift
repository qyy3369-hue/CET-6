import AppKit

@MainActor
final class AppEditShortcuts: NSObject, NSMenuItemValidation {
    private var keyMonitor: Any?
    private weak var dismissingSheetFrom: NSWindow?

    func install() {
        installMenus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sheetDidEnd(_:)), name: NSWindow.didEndSheetNotification, object: nil
        )
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isQuitShortcut(event) {
                if !event.isARepeat { self?.quitApplication(nil) }
                return nil
            }
            return Self.commandEquivalent(for: event)
        }
    }

    func uninstall() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didEndSheetNotification, object: nil)
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func installMenus() {
        let menuBar = NSApp.mainMenu ?? NSMenu()
        let appMenu: NSMenu
        if let installedMenu = menuBar.items.first?.submenu {
            appMenu = installedMenu
        } else {
            let appItem = NSMenuItem()
            appMenu = NSMenu(title: "Goals")
            appItem.submenu = appMenu
            menuBar.insertItem(appItem, at: 0)
        }
        let quitAction = #selector(NSApplication.terminate(_:))
        let quitItem = appMenu.items.first { $0.action == quitAction }
            ?? appMenu.addItem(withTitle: "退出 Goals", action: quitAction, keyEquivalent: "q")
        quitItem.action = #selector(quitApplication(_:))
        quitItem.target = self
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command

        let editMenu = NSMenu(title: "编辑")
        let undoItem = editMenu.addItem(withTitle: "撤销", action: #selector(undoEditing(_:)), keyEquivalent: "z")
        undoItem.target = self
        let redoItem = editMenu.addItem(withTitle: "重做", action: #selector(redoEditing(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menuBar.addItem(editItem)
        NSApp.mainMenu = menuBar
    }

    @objc private func quitApplication(_ sender: Any?) {
        guard dismissingSheetFrom == nil else { return }
        if let parent = NSApp.windows.first(where: {
            guard let sheet = $0.attachedSheet else { return false }
            return sheet.attachedSheet == nil
        }), let sheet = parent.attachedSheet {
            dismissingSheetFrom = parent
            parent.endSheet(sheet, returnCode: .cancel)
            return
        }
        NSApp.terminate(sender)
    }

    @objc private func sheetDidEnd(_ notification: Notification) {
        guard let parent = notification.object as? NSWindow, parent === dismissingSheetFrom else { return }
        dismissingSheetFrom = nil
        // Let AppKit and SwiftUI finish dismissing the cancelled sheet before quitting.
        DispatchQueue.main.async { [weak self] in self?.quitApplication(nil) }
    }

    private var activeUndoManager: UndoManager? {
        let window = NSApp.keyWindow
        return window?.firstResponder?.undoManager ?? window?.undoManager
    }

    @objc private func undoEditing(_ sender: Any?) {
        guard let manager = activeUndoManager, manager.canUndo else { return }
        manager.undo()
    }

    @objc private func redoEditing(_ sender: Any?) {
        guard let manager = activeUndoManager, manager.canRedo else { return }
        manager.redo()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEditing(_:)): activeUndoManager?.canUndo == true
        case #selector(redoEditing(_:)): activeUndoManager?.canRedo == true
        default: true
        }
    }

    private nonisolated static func shortcutModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.control, .command, .shift, .option, .function])
    }

    private nonisolated static func isQuitShortcut(_ event: NSEvent) -> Bool {
        shortcutModifiers(for: event) == .command && event.charactersIgnoringModifiers?.lowercased() == "q"
    }

    private nonisolated static func commandEquivalent(for event: NSEvent) -> NSEvent {
        let modifiers = shortcutModifiers(for: event)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return event }

        let replacement: String
        let commandModifiers: NSEvent.ModifierFlags
        switch (modifiers, key) {
        case (.control, "a"), (.control, "c"), (.control, "v"), (.control, "x"), (.control, "z"):
            replacement = key
            commandModifiers = .command
        case (.control, "y"), ([.control, .shift], "z"):
            replacement = "Z"
            commandModifiers = [.command, .shift]
        default:
            return event
        }

        // Dispatch the normal Command shortcut so the active control handles the edit.
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags.subtracting([.control, .shift]).union(commandModifiers),
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: replacement,
            charactersIgnoringModifiers: replacement,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }
}
