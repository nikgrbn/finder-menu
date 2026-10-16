import Cocoa
import FinderSync

@objc(FinderMenuSync)
class FinderMenuSync: FIFinderSync {
    override init() {
        super.init()
        watchDrives()
        // Drives come and go while Finder runs, and the settings window can turn them off or on.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(watchDrives(_:)), name: NSWorkspace.didMountNotification, object: nil)
        workspace.addObserver(self, selector: #selector(watchDrives(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(watchDrives(_:)), name: otherDrivesChanged, object: nil)
    }

    // Finder shows the menu only in these folders and the folders inside them. "/" is just the startup
    // disk: Finder treats every other drive (USB drives, disk images, network shares, FUSE mounts) as a
    // separate root, so list each one too. Finder then shows this app's icon for each listed drive except
    // the startup disk in its sidebar. Nothing above a drive can be listed instead, hence the setting.
    @objc private func watchDrives(_ notification: Notification? = nil) {
        var roots = [URL(fileURLWithPath: "/")]
        if showsOnOtherDrives {
            roots += FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? []
        }
        FIFinderSyncController.default().directoryURLs = Set(roots)
    }

    // The top of a drive, where there's no parent folder to go to.
    private func isDriveRoot(_ url: URL) -> Bool {
        (FIFinderSyncController.default().directoryURLs ?? []).contains { $0.path == url.path }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else { return nil }
        Self.inOpenOrSaveDialog = Self.isOpenOrSaveDialog()
        let menu = NSMenu(title: "")
        for item in menuItems where !isHidden(item.id) {
            let entry = NSMenuItem(title: NSLocalizedString(item.title, comment: ""), action: nil, keyEquivalent: "")
            switch item.id {
            case "new-file":
                let templates = fileTemplates
                if templates.isEmpty {
                    entry.action = #selector(newFile(_:))
                } else {
                    entry.title = NSLocalizedString("New File", comment: "")
                    entry.submenu = Self.newFileMenu(templates)
                }
            case "terminal": entry.action = #selector(openTerminal(_:))
            case "open-with": entry.submenu = Self.openWithMenu()
            case "copy-path": entry.action = #selector(copyPath(_:))
            case "copy-name": entry.action = #selector(copyName(_:))
            case "parent-folder":
                guard let dir = currentFolder, !isDriveRoot(dir) else { continue }
                entry.action = #selector(goUp(_:))
            default: continue
            }
            entry.image = Self.symbol(item.symbol)
            menu.addItem(entry)
        }
        return menu.items.isEmpty ? nil : menu
    }

    // Other apps' Open and Save dialogs show this menu too, in that app's appearance, which can differ
    // from the system's (an app with its own dark theme on a Mac in Light Mode). The extension can't see
    // it, so symbol() would paint black icons on a dark menu. The dialog's own items have no icons, so
    // ours go too. The menu is for the window under the pointer: Finder's (a window or the Desktop) or a dialog.
    private static var inOpenOrSaveDialog = false

    private static func isOpenOrSaveDialog() -> Bool {
        guard let pointer = CGEvent(source: nil)?.location,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        // Front to back, skipping invisible windows and those above app windows: menus, the menu bar and
        // the Dock, whose window covers the whole screen.
        let clicked = windows.first { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer <= NSWindow.Level.modalPanel.rawValue,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.contains(pointer)
        }
        guard let pid = clicked?[kCGWindowOwnerPID as String] as? pid_t else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.finder"
    }

    // Finder drops the template flag when it copies the menu, so SF Symbols would always render
    // black. Instead, bake the current appearance's text color into a plain bitmap each time.
    static func symbol(_ name: String, appearance: NSAppearance = NSApplication.shared.effectiveAppearance) -> NSImage? {
        // Show icons in settings, on by default only where Finder's own items have icons (macOS 26 and later).
        // App icons, as in Open Folder With, don't come from here: Finder's own Open With shows them on every version.
        guard showsMenuIcons, !inOpenOrSaveDialog else { return nil }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var color = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        return flatten(base, size: base.size, tint: color)
    }

    // Finder receives a copy of the whole menu on every right-click, images included. An app icon
    // carries every size up to 1024px, so a few of them made that copy hundreds of MB and the menu
    // slow to open. Draw each image once, at menu size, into a single small bitmap.
    static func flatten(_ image: NSImage, size: NSSize, tint: NSColor? = nil) -> NSImage? {
        let scale = 2.0
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        if let tint {
            tint.set()
            rect.fill(using: .sourceAtop)
        }
        NSGraphicsContext.restoreGraphicsState()
        let flat = NSImage(size: size)
        flat.addRepresentation(rep)
        return flat
    }

    static func openWithMenu() -> NSMenu {
        let sub = NSMenu(title: "")
        for (i, editor) in editors.enumerated() {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.id) else { continue }
            let item = sub.addItem(withTitle: editor.name, action: #selector(FinderMenuSync.openWith(_:)), keyEquivalent: "")
            item.tag = i // Finder copies the menu, so the tag is how the action knows which app was picked.
            item.image = flatten(NSWorkspace.shared.icon(forFile: appURL.path), size: NSSize(width: 16, height: 16))
        }
        if !sub.items.isEmpty { sub.addItem(.separator()) }
        sub.addItem(withTitle: NSLocalizedString("Other App…", comment: ""), action: #selector(FinderMenuSync.openWithOther(_:)), keyEquivalent: "")
            .image = symbol("ellipsis.circle")
        return sub
    }

    // New File… (the name dialog, with Save as template) comes first; below it, templates are
    // one-click items, and Manage Templates… opens the settings window, where they can be removed.
    static func newFileMenu(_ templates: [FileTemplate]) -> NSMenu {
        let sub = NSMenu(title: "")
        sub.addItem(withTitle: NSLocalizedString("New File…", comment: ""), action: #selector(FinderMenuSync.newFile(_:)), keyEquivalent: "")
            .image = symbol("doc.badge.plus")
        sub.addItem(.separator())
        let icon = symbol("doc") // One bitmap shared by every template item.
        for template in templates {
            sub.addItem(withTitle: template.filename, action: #selector(FinderMenuSync.newFileFromTemplate(_:)), keyEquivalent: "")
                .image = icon
        }
        sub.addItem(.separator())
        sub.addItem(withTitle: NSLocalizedString("Manage Templates…", comment: ""), action: #selector(FinderMenuSync.manageTemplates(_:)), keyEquivalent: "")
            .image = symbol("gearshape")
        return sub
    }

    @objc func goUp(_ sender: AnyObject?) {
        guard let dir = currentFolder else { return }
        callHelper("up", dir.path)
    }

    private var currentFolder: URL? { FIFinderSyncController.default().targetedURL() }
    private var selection: [URL] { FIFinderSyncController.default().selectedItemURLs() ?? [] }
    // Right-clicked a single item → that item (the helper uses its folder); otherwise the folder you're in.
    private var clickedTarget: URL? { selection.count == 1 ? selection[0] : currentFolder }

    @objc func openWith(_ sender: AnyObject?) {
        guard let tag = (sender as? NSMenuItem)?.tag, editors.indices.contains(tag),
              let target = clickedTarget else { return }
        callHelper("openwith", target.path, app: editors[tag].id)
    }

    @objc func openWithOther(_ sender: AnyObject?) {
        guard let target = clickedTarget else { return }
        callHelper("openwith", target.path)
    }

    @objc func newFile(_ sender: AnyObject?) {
        guard let dir = currentFolder else { return }
        callHelper("newfile", dir.path)
    }

    // Finder copies the menu, so find the template by the item's title (file names are unique).
    // An index could point at a different template if the list changed after the menu was built.
    @objc func newFileFromTemplate(_ sender: AnyObject?) {
        guard let dir = currentFolder,
              let title = (sender as? NSMenuItem)?.title,
              let template = fileTemplates.first(where: { $0.filename == title }) else { return }
        callHelper("newfile", dir.path, template: template.id)
    }

    // The extension can only read settings, so the helper's settings window removes templates.
    @objc func manageTemplates(_ sender: AnyObject?) {
        callHelper("settings")
    }

    @objc func openTerminal(_ sender: AnyObject?) {
        guard let target = clickedTarget else { return }
        callHelper("terminal", target.path)
    }

    @objc func copyPath(_ sender: AnyObject?) {
        copyToPasteboard(\.path)
    }

    // The name as stored, with its extension even when Finder hides it. "/" has no name of its own,
    // so use the startup disk's, which is what Finder shows there.
    @objc func copyName(_ sender: AnyObject?) {
        copyToPasteboard { url in
            url.path == "/" ? (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "/" : url.lastPathComponent
        }
    }

    // One line per selected item, or the folder you're in when nothing is selected.
    private func copyToPasteboard(_ text: (URL) -> String) {
        let urls = selection.isEmpty ? [currentFolder].compactMap { $0 } : selection
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(text).joined(separator: "\n"), forType: .string)
    }

    // The extension is sandboxed, so file creation and app launching happen in the helper app.
    private func callHelper(_ action: String, _ path: String? = nil, app: String? = nil, template: String? = nil) {
        var c = URLComponents()
        c.scheme = "findermenu"
        c.host = action
        let items = [("path", path), ("app", app), ("template", template)]
            .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if !items.isEmpty { c.queryItems = items }
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
