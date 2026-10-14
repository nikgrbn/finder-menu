import Cocoa
import os
import Security
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var handledURL = false
    private var settingsWindow: SettingsWindowController?
    // Kept while the New File alert is open, so Use File as Template… can fill the name field.
    private var newFileDialogState: NewFileDialogState?

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        guard sentByOurExtension() else {
            // Logger rather than NSLog, which macOS logs as <private>. The links stay redacted.
            Logger(subsystem: "local.findermenu", category: "links")
                .notice("Ignored a findermenu:// link that didn't come from the Finder extension: \(urls.map(\.absoluteString))")
            finish()
            return
        }
        for url in urls {
            guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            // Manage Templates… doesn't act on a folder.
            if c.host == "settings" { showSettings(); continue }
            // Use as Template… passes a file path, not a folder.
            if c.host == "usetemplate" {
                guard let path = c.queryItems?.first(where: { $0.name == "path" })?.value,
                      let source = templateSourceFile(atPath: path) else { continue }
                newFile(in: source.deletingLastPathComponent().path, fromSource: source)
                continue
            }
            guard let path = c.queryItems?.first(where: { $0.name == "path" })?.value,
                  let dir = folder(for: path) else { continue }
            switch c.host {
            case "newfile":
                // The file name comes from saved settings, not the URL — only the template id travels in the link.
                let templateID = c.queryItems?.first(where: { $0.name == "template" })?.value
                if let templateID {
                    guard let template = fileTemplate(id: templateID) else { continue }
                    newFile(in: dir, from: template)
                } else {
                    newFile(in: dir)
                }
            case "terminal": openTerminal(at: dir); return
            case "openwith":
                let appID = c.queryItems?.first(where: { $0.name == "app" })?.value
                // No app means "Other App…", where the user picks one themselves.
                if let appID, !editors.contains(where: { $0.id == appID }) { continue }
                openFolder(dir, appID: appID)
                return
            case "up": goUp(from: dir)
            default: break
            }
        }
        // A New File link can save a template while the settings window is open.
        settingsWindow?.reloadTemplates()
        finish()
    }

    // Before any link is handled: text fields get ⌘V, ⌘C, ⌘A and ⌘Z from the Edit menu, so the New File
    // dialog needs it too, even though the menu bar only shows with the settings window.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched by a menu item, a findermenu:// link arrives right away; otherwise the user opened the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.handledURL { self.showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // Opened directly, the helper behaves like a regular app (Dock icon, ⌘W, ⌘Q) and quits with its window.
    private func showSettings() {
        if settingsWindow == nil {
            NSApp.setActivationPolicy(.regular)
            let controller = SettingsWindowController()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window,
                                                   queue: .main) { _ in NSApp.terminate(nil) }
            settingsWindow = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: NSLocalizedString("About Finder Menu", comment: ""), action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: NSLocalizedString("Quit Finder Menu", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: NSLocalizedString("Edit", comment: ""))
        editMenu.addItem(withTitle: NSLocalizedString("Undo", comment: ""), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: NSLocalizedString("Redo", comment: ""), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: ""), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: ""), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: ""), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: ""), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: NSLocalizedString("Window", comment: ""))
        windowMenu.addItem(withTitle: NSLocalizedString("Close", comment: ""), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    // The standard About panel, with a link to the project under the version.
    @objc private func showAbout(_ sender: Any?) {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let link = NSAttributedString(string: repositoryName, attributes: [
            .link: repositoryURL, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: centered,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: link])
    }

    // A menu action is done. Quit, unless the settings window is open.
    private func finish() {
        if settingsWindow == nil { NSApp.terminate(nil) }
    }

    // Any app can send a findermenu:// link, and so can a website once the browser asks. Opening a
    // folder they pick in a terminal or IDE can run code from it (a git-aware prompt, an IDE's
    // folder-open tasks), so only accept links sent by the extension bundled with this app, matched
    // by code signature hash. Fails closed if the sender can't be identified (e.g. it has quit).
    private func sentByOurExtension() -> Bool {
        guard let token = NSAppleEventManager.shared().currentAppleEvent?
                  .attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
              let ext = Bundle.main.builtInPlugInsURL?.appendingPathComponent("FinderMenuExtension.appex")
        else { return false }
        var sender: SecCode?, bundled: SecStaticCode?, info: CFDictionary?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &sender) == errSecSuccess,
              let sender,
              SecStaticCodeCreateWithPath(ext as CFURL, [], &bundled) == errSecSuccess,
              let bundled,
              SecCodeCopySigningInformation(bundled, [], &info) == errSecSuccess,
              let cdhash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data,
              SecRequirementCreateWithString("cdhash H\"\(cdhash.map { String(format: "%02x", $0) }.joined())\"" as CFString,
                                             [], &requirement) == errSecSuccess
        else { return false }
        return SecCodeCheckValidity(sender, [], requirement) == errSecSuccess
    }

    // Moves the Finder window showing `dir` (front-most match, else the front window) up one level.
    private func goUp(from dir: String) {
        let parent = (dir as NSString).deletingLastPathComponent
        let script = """
        tell application "Finder"
            set dest to (POSIX file \(appleScriptString(parent)) as alias)
            repeat with w in Finder windows
                try
                    -- Case-only paths can name different folders on case-sensitive volumes.
                    considering case
                        if POSIX path of (target of w as alias) is \(appleScriptString(dir + "/")) then
                            set target of w to dest
                            return
                        end if
                    end considering
                end try
            end repeat
            if (count of Finder windows) > 0 then set target of front Finder window to dest
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { NSLog("Finder Menu go-up failed: \(error)") }
    }

    // Uses the terminal picked in settings (or with `finder-menu terminal <app>`), otherwise the first installed one.
    private func openTerminal(at dir: String) {
        let ws = NSWorkspace.shared
        for id in [chosenTerminal].compactMap({ $0 }) + terminals.map(\.id) {
            guard let app = ws.urlForApplication(withBundleIdentifier: id) else { continue }
            let quit: (NSRunningApplication?, Error?) -> Void = { _, _ in DispatchQueue.main.async { self.finish() } }
            switch terminals.first(where: { $0.id == id })?.launch ?? .openFolder {
            case .openFolder:
                open(dir, withAppAt: app)
            case .link(let makeURL):
                guard let url = makeURL(dir) else { finish(); return }
                ws.open(url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: quit)
            case .arguments(let makeArguments):
                let config = NSWorkspace.OpenConfiguration()
                config.arguments = makeArguments(dir)
                config.createsNewApplicationInstance = true
                ws.openApplication(at: app, configuration: config, completionHandler: quit)
            }
            return
        }
        finish()
    }

    // No app ID means "Other App…": let the user pick any app.
    private func openFolder(_ dir: String, appID: String?) {
        if let appID {
            open(dir, withAppAt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        let openFormat = NSLocalizedString("Open “%@” with:", comment: "")
        panel.message = String(format: openFormat, (dir as NSString).lastPathComponent)
        panel.prompt = NSLocalizedString("Open", comment: "")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        open(dir, withAppAt: panel.runModal() == .OK ? panel.url : nil)
    }

    private func open(_ dir: String, withAppAt app: URL?) {
        guard let app else { finish(); return }
        NSWorkspace.shared.open([URL(fileURLWithPath: dir, isDirectory: true)], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { self.finish() }
        }
    }

    private func newFile(in dir: String) {
        createFile(in: dir, suggested: "untitled.txt", ask: true)
    }

    // Right-click Use as Template…: same dialog as Use File as Template…, with the file already chosen.
    private func newFile(in dir: String, fromSource source: URL) {
        createFile(in: dir, suggested: source.lastPathComponent, ask: true, saveAsTemplate: true, source: source)
    }

    // One click from the New File submenu: copy the stored file. If there is no copy (an old
    // name-only template), create an empty file. If the name is taken, pick the next free name
    // the way Finder does (notes.md → notes 2.md).
    private func newFile(in dir: String, from template: FileTemplate) {
        guard isValidFilename(template.filename) else { return }
        for _ in 0..<50 {
            let name = unusedFilename(template.filename, in: dir)
            let dest = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(name))
            do {
                if let stored = storedTemplateFile(template) {
                    try FileManager.default.copyItem(at: stored, to: dest)
                    stripQuarantine(at: dest)
                } else {
                    try Data().write(to: dest, options: .withoutOverwriting)
                }
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                return
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                NSLog("Finder Menu couldn't create a file from a template: \(error)")
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("New File", comment: "")
                alert.informativeText = NSLocalizedString("⚠️ Couldn't create the file here (no permission?).", comment: "")
                alert.runModal()
                return
            }
        }
    }

    private func createFile(in dir: String, suggested: String, ask: Bool,
                            saveAsTemplate: Bool = false, source: URL? = nil) {
        var name = suggested
        var saveAsTemplate = saveAsTemplate
        var source = source
        var problem: String?
        while true {
            if ask || problem != nil {
                let inFormat = NSLocalizedString("In: %@", comment: "")
                let inString = String(format: inFormat, (dir as NSString).abbreviatingWithTildeInPath)
                let info = (problem.map { $0 + "\n\n" } ?? "") + inString
                guard let options = askFileName(info: info, suggested: name,
                                                saveAsTemplate: saveAsTemplate, source: source) else { return }
                name = options.name.trimmingCharacters(in: .whitespacesAndNewlines)
                saveAsTemplate = options.saveAsTemplate
                source = options.source
            }
            let dest = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(name))
            if !isValidFilename(name) {
                problem = NSLocalizedString("⚠️ That isn't a valid file name.", comment: "")
                continue
            }
            // Picking a file that already sits in this folder (same path) isn't a conflict: only
            // the template store needs a copy. Creating a second file would fail with "already exists".
            let sourceFile = source?.resolvingSymlinksInPath().standardizedFileURL
            let creatingInPlace = sourceFile == dest.resolvingSymlinksInPath().standardizedFileURL
            do {
                if let source, !creatingInPlace {
                    // A separate existence check cannot prevent another process from creating the same path.
                    try FileManager.default.copyItem(at: source, to: dest)
                    stripQuarantine(at: dest)
                } else if source == nil {
                    try Data().write(to: dest, options: .withoutOverwriting)
                }
                if saveAsTemplate {
                    if let source {
                        saveFileTemplate(copying: source, as: name)
                    } else {
                        saveFileTemplate(filename: name)
                    }
                    settingsWindow?.reloadTemplates()
                }
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                return
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                let existsFormat = NSLocalizedString("⚠️ \"%@\" already exists.", comment: "")
                problem = String(format: existsFormat, name)
            } catch {
                problem = NSLocalizedString("⚠️ Couldn't create the file here (no permission?).", comment: "")
            }
        }
    }

    private struct NewFileOptions {
        var name: String
        var saveAsTemplate: Bool
        var source: URL?
    }

    // Holds the controls the "Use File as Template…" button updates while the alert is modal.
    private final class NewFileDialogState: NSObject {
        var source: URL?
        weak var nameField: NSTextField?
        weak var sourceLabel: NSTextField?
        weak var saveBox: NSButton?
        weak var stack: NSStackView?
        weak var alert: NSAlert?

        @objc func pickSource(_ sender: Any?) {
            guard let url = pickTemplateSourceFile() else { return }
            source = url
            nameField?.stringValue = url.lastPathComponent
            let fromFormat = NSLocalizedString("From: %@", comment: "")
            sourceLabel?.stringValue = String(format: fromFormat, (url.path as NSString).abbreviatingWithTildeInPath)
            sourceLabel?.isHidden = false
            saveBox?.state = .on
            guard let stack, let alert else { return }
            stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
            alert.accessoryView = stack
            alert.window.layoutIfNeeded()
        }
    }

    private func askFileName(info: String, suggested: String, saveAsTemplate: Bool, source: URL?) -> NewFileOptions? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New File", comment: "")
        alert.informativeText = info
        alert.addButton(withTitle: NSLocalizedString("Create", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let field = NSTextField(frame: .zero)
        field.stringValue = suggested
        field.placeholderString = "name.ext"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let sourceLabel = NSTextField(labelWithString: "")
        sourceLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let source {
            let fromFormat = NSLocalizedString("From: %@", comment: "")
            sourceLabel.stringValue = String(format: fromFormat, (source.path as NSString).abbreviatingWithTildeInPath)
        } else {
            sourceLabel.isHidden = true
        }

        let saveBox = NSButton(checkboxWithTitle: NSLocalizedString("Save as template", comment: ""), target: nil, action: nil)
        saveBox.state = saveAsTemplate ? .on : .off

        let state = NewFileDialogState()
        state.source = source
        state.nameField = field
        state.sourceLabel = sourceLabel
        state.saveBox = saveBox
        state.alert = alert

        let addButton = NSButton(title: NSLocalizedString("Use File as Template…", comment: ""),
                                 target: state, action: #selector(NewFileDialogState.pickSource(_:)))
        addButton.controlSize = .small
        addButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [saveBox, spacer, addButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        let width = max(320, saveBox.fittingSize.width + addButton.fittingSize.width + 12)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        sourceLabel.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView(views: [field, sourceLabel, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(6, after: field)
        stack.setCustomSpacing(12, after: sourceLabel)
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        state.stack = stack
        newFileDialogState = state
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field

        // The Finder extension can't hand focus to the helper, and macOS refuses to bring forward an app
        // with no windows on screen. So ask once the alert is showing, or typing still goes to Finder.
        RunLoop.main.perform(inModes: [.modalPanel]) { NSApp.activate(ignoringOtherApps: true) }
        defer { newFileDialogState = nil }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return NewFileOptions(name: field.stringValue, saveAsTemplate: saveBox.state == .on, source: state.source)
    }
}

// Opens a panel for Use File as Template…. Only picks a file; Create stores the copy under the typed name.
private func pickTemplateSourceFile() -> URL? {
    let panel = NSOpenPanel()
    panel.message = NSLocalizedString("Choose a file to use as a template:", comment: "")
    panel.prompt = NSLocalizedString("Choose", comment: "")
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = false
    panel.resolvesAliases = true
    RunLoop.main.perform(inModes: [.modalPanel]) { NSApp.activate(ignoringOtherApps: true) }
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url
}

// Stores a template copy, asking before replacing a template that already uses this name.
private func saveFileTemplate(copying source: URL, as filename: String) {
    do {
        try addFileTemplate(copying: source, as: filename, replace: false)
    } catch TemplateFileError.duplicate(let name) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("\"%@\" is already a template.", comment: ""), name)
        alert.informativeText = NSLocalizedString("Replace the saved template with this file?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Replace", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try addFileTemplate(copying: source, as: filename, replace: true)
        } catch {
            NSLog("Finder Menu couldn't replace a template: \(error)")
            reportTemplateAddFailure(filename)
        }
    } catch {
        NSLog("Finder Menu couldn't add a template: \(error)")
        reportTemplateAddFailure(filename)
    }
}

private func reportTemplateAddFailure(_ name: String) {
    let alert = NSAlert()
    alert.messageText = String(format: NSLocalizedString("Couldn't add \"%@\" as a template.", comment: ""), name)
    alert.runModal()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
