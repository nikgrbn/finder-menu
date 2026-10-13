import Cocoa
import UniformTypeIdentifiers

// Where to read the docs, report a bug or see the source. Linked from settings and the About panel.
let repositoryURL = URL(string: "https://github.com/nikgrbn/finder-menu")!
let repositoryName = "github.com/nikgrbn/finder-menu"

// Shown when Finder Menu.app is opened directly (Spotlight, Finder, `finder-menu settings`).
// Every change is saved right away and applies on the next right-click.
final class SettingsWindowController: NSWindowController {
    private let terminalPopup = NSPopUpButton()
    private let chooseOtherTag = 1
    private let templatesStack = NSStackView()

    convenience init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Finder Menu Settings", comment: "")
        self.init(window: window)
        window.contentView = makeContent()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    private func makeContent() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let name = NSTextField(labelWithString: "Finder Menu")
        name.font = .boldSystemFont(ofSize: 15)
        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let version = NSTextField(labelWithString: String(format: NSLocalizedString("Version %@", comment: ""), versionNumber))
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        let link = LinkButton(title: repositoryName, url: repositoryURL)
        let titles = NSStackView(views: [name, version, link])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12

        let checkboxes = menuItems.enumerated().map { index, item in
            let box = NSButton(checkboxWithTitle: NSLocalizedString(item.title, comment: ""), target: self, action: #selector(toggleItem(_:)))
            box.tag = index
            box.state = isHidden(item.id) ? .off : .on
            return box
        }
        let drivesBox = NSButton(checkboxWithTitle: NSLocalizedString("Also on external and network drives", comment: ""),
                                 target: self, action: #selector(toggleOtherDrives(_:)))
        drivesBox.state = showsOnOtherDrives ? .on : .off
        let iconsBox = NSButton(checkboxWithTitle: NSLocalizedString("Show icons", comment: ""), target: self, action: #selector(toggleIcons(_:)))
        iconsBox.state = showsMenuIcons ? .on : .off

        terminalPopup.target = self
        terminalPopup.action = #selector(pickTerminal(_:))
        terminalPopup.isEnabled = !isHidden("terminal")
        reloadTerminalPopup()

        // .width so each row stretches; Remove can sit on the trailing edge.
        templatesStack.orientation = .vertical
        templatesStack.alignment = .width
        templatesStack.spacing = 6
        templatesStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        reloadTemplates()

        let note = NSTextField(labelWithString: NSLocalizedString("Changes apply the next time you right-click in Finder.", comment: ""))
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let itemsLabel = Self.sectionLabel(NSLocalizedString("Show in the right-click menu", comment: ""))
        let terminalLabel = Self.sectionLabel(NSLocalizedString("Open Terminal Here uses", comment: ""))
        let templatesLabel = Self.sectionLabel(NSLocalizedString("New File templates", comment: ""))

        let stack = NSStackView(views: [header, itemsLabel] + checkboxes + [drivesBox, iconsBox, terminalLabel, terminalPopup, templatesLabel, templatesStack, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(10, after: itemsLabel)
        stack.setCustomSpacing(14, after: checkboxes.last!)
        stack.setCustomSpacing(20, after: iconsBox)
        stack.setCustomSpacing(10, after: terminalLabel)
        stack.setCustomSpacing(20, after: terminalPopup)
        stack.setCustomSpacing(10, after: templatesLabel)
        stack.setCustomSpacing(20, after: templatesStack)
        terminalPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        // Match the full settings column, not just the terminal popup's intrinsic width.
        templatesStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // NSStackView ignores its trailing inset, so pin the margins explicitly.
        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        return content
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    // setContentSize keeps the bottom edge in place; keep the title bar there instead.
    private func resizeToFit() {
        guard let window, let content = window.contentView else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    func reloadTemplates() {
        templatesStack.views.forEach { $0.removeFromSuperview() }
        let templates = fileTemplates
        if templates.isEmpty {
            let empty = NSTextField(labelWithString: NSLocalizedString("No templates yet.", comment: ""))
            empty.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            empty.textColor = .tertiaryLabelColor
            templatesStack.addArrangedSubview(empty)
        } else {
            for template in templates {
                templatesStack.addArrangedSubview(templateRow(template))
            }
            if templates.count > 1 {
                let removeAll = smallButton(NSLocalizedString("Remove All", comment: ""), action: #selector(removeAllTemplates(_:)))
                let row = NSStackView(views: [NSView(), removeAll])
                row.orientation = .horizontal
                row.alignment = .centerY
                row.distribution = .fill
                // A little apart from the rows, so it doesn't read as another template.
                templatesStack.setCustomSpacing(12, after: templatesStack.arrangedSubviews.last!)
                templatesStack.addArrangedSubview(row)
            }
        }
        resizeToFit()
    }

    private func templateRow(_ template: FileTemplate) -> NSView {
        let name = NSTextField(labelWithString: template.filename)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let remove = smallButton(NSLocalizedString("Remove", comment: ""), action: #selector(removeTemplate(_:)))
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.identifier = NSUserInterfaceItemIdentifier(template.id)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(name)
        row.addSubview(remove)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -8),
            remove.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            remove.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            remove.topAnchor.constraint(equalTo: row.topAnchor),
            remove.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    // A regular push button at small size: normal padding, compact enough for a list row.
    private func smallButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    // By id, not row: the rows can be out of date if templates changed since they were built.
    @objc private func removeTemplate(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        removeFileTemplate(id: id)
        reloadTemplates()
    }

    @objc private func removeAllTemplates(_ sender: Any?) {
        fileTemplates = []
        reloadTemplates()
    }

    @objc private func toggleItem(_ sender: NSButton) {
        let item = menuItems[sender.tag]
        setHidden(item.id, sender.state == .off)
        if item.id == "terminal" { terminalPopup.isEnabled = sender.state == .on }
    }

    // The extension picks its drives when it starts, not on every right-click, so tell it to pick again.
    @objc private func toggleOtherDrives(_ sender: NSButton) {
        showsOnOtherDrives = sender.state == .on
        DistributedNotificationCenter.default().postNotificationName(otherDrivesChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @objc private func toggleIcons(_ sender: NSButton) {
        showsMenuIcons = sender.state == .on
    }

    // Automatic, the installed terminals Finder Menu knows, a previously chosen other app, then "Other App…".
    private func reloadTerminalPopup() {
        let ws = NSWorkspace.shared
        let installed = terminals.filter { ws.urlForApplication(withBundleIdentifier: $0.id) != nil }
        var choices = installed.map { (id: $0.id, name: $0.name) }
        if let chosen = chosenTerminal, !choices.contains(where: { $0.id == chosen }),
           let url = ws.urlForApplication(withBundleIdentifier: chosen) {
            choices.append((chosen, url.deletingPathExtension().lastPathComponent))
        }

        let menu = NSMenu()
        let autoFormat = NSLocalizedString("Automatic (%@)", comment: "")
        menu.addItem(withTitle: String(format: autoFormat, installed.first?.name ?? "Terminal"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for choice in choices {
            let item = menu.addItem(withTitle: choice.name, action: nil, keyEquivalent: "")
            item.representedObject = choice.id
            if let url = ws.urlForApplication(withBundleIdentifier: choice.id) {
                let icon = ws.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("Other App…", comment: ""), action: nil, keyEquivalent: "").tag = chooseOtherTag
        terminalPopup.menu = menu

        let selected = menu.items.first { ($0.representedObject as? String) == chosenTerminal }
        terminalPopup.select(selected ?? menu.items.first)
    }

    @objc private func pickTerminal(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == chooseOtherTag {
            let panel = NSOpenPanel()
            panel.message = NSLocalizedString("Choose the app for Open Terminal Here:", comment: "")
            panel.prompt = NSLocalizedString("Choose", comment: "")
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
                chosenTerminal = id
            }
            reloadTerminalPopup()
            return
        }
        chosenTerminal = item.representedObject as? String
    }
}

// Text that looks and acts like a web link: link color, a pointing hand, opens in the default browser.
private final class LinkButton: NSButton {
    private var url: URL!

    convenience init(title: String, url: URL) {
        self.init(frame: .zero)
        self.url = url
        isBordered = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        toolTip = url.absoluteString
        target = self
        action = #selector(openLink(_:))
    }

    // Labels line up by their text, 2 points in from their frame. Do the same, so the link lines up with them.
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func openLink(_ sender: Any?) {
        NSWorkspace.shared.open(url)
    }
}
