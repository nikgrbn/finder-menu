import Cocoa
import FinderSync

@objc(FinderMenuSync)
class FinderMenuSync: FIFinderSync {
    override init() {
        super.init()
        // Show the menu in every folder on the Mac.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else { return nil }
        let menu = NSMenu(title: "")
        for item in menuItems where !isHidden(item.id) {
            let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            switch item.id {
            case "new-file":
                let templates = fileTemplates
                if templates.isEmpty {
                    entry.action = #selector(newFile(_:))
                } else {
                    entry.title = "New File"
                    entry.submenu = Self.newFileMenu(templates)
                }
            case "terminal": entry.action = #selector(openTerminal(_:))
            case "open-with": entry.submenu = Self.openWithMenu()
            case "copy-path": entry.action = #selector(copyPath(_:))
            case "parent-folder":
                guard let dir = currentFolder, dir.path != "/" else { continue }
                entry.action = #selector(goUp(_:))
            default: continue
            }
            entry.image = Self.symbol(item.symbol)
            menu.addItem(entry)
        }
        return menu.items.isEmpty ? nil : menu
    }

    // Finder drops the template flag when it copies the menu, so SF Symbols would always render
    // black. Instead, bake the current appearance's text color into a plain bitmap each time.
    static func symbol(_ name: String, appearance: NSAppearance = NSApplication.shared.effectiveAppearance) -> NSImage? {
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
        sub.addItem(withTitle: "Other App…", action: #selector(FinderMenuSync.openWithOther(_:)), keyEquivalent: "")
            .image = symbol("ellipsis.circle")
        return sub
    }

    // Templates become one-click items; Custom… keeps the name dialog (with Save as template /
    // Open after creation). Finder copies the menu, so each template item carries its id.
    static func newFileMenu(_ templates: [FileTemplate]) -> NSMenu {
        let sub = NSMenu(title: "")
        for template in templates {
            let item = sub.addItem(withTitle: template.filename, action: #selector(FinderMenuSync.newFileFromTemplate(_:)), keyEquivalent: "")
            item.representedObject = template.id
            item.image = symbol("doc")
        }
        sub.addItem(.separator())
        sub.addItem(withTitle: "Custom…", action: #selector(FinderMenuSync.newFile(_:)), keyEquivalent: "")
            .image = symbol("doc.badge.plus")
        sub.addItem(withTitle: "Manage Templates…", action: #selector(FinderMenuSync.manageTemplates(_:)), keyEquivalent: "")
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

    @objc func newFileFromTemplate(_ sender: AnyObject?) {
        guard let dir = currentFolder,
              let id = (sender as? NSMenuItem)?.representedObject as? String,
              fileTemplate(id: id) != nil else { return }
        callHelper("newfile", dir.path, template: id)
    }

    @objc func manageTemplates(_ sender: AnyObject?) {
        // Path is unused for this action; still required so the helper accepts the link.
        guard let dir = currentFolder else { return }
        callHelper("managetemplates", dir.path)
    }

    @objc func openTerminal(_ sender: AnyObject?) {
        guard let target = clickedTarget else { return }
        callHelper("terminal", target.path)
    }

    @objc func copyPath(_ sender: AnyObject?) {
        let urls = selection.isEmpty ? [currentFolder].compactMap { $0 } : selection
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    // The extension is sandboxed, so file creation and app launching happen in the helper app.
    private func callHelper(_ action: String, _ path: String, app: String? = nil, template: String? = nil) {
        var c = URLComponents()
        c.scheme = "findermenu"
        c.host = action
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        if let app { c.queryItems?.append(URLQueryItem(name: "app", value: app)) }
        if let template { c.queryItems?.append(URLQueryItem(name: "template", value: template)) }
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
