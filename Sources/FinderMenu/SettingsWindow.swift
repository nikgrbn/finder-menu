import Cocoa
import UniformTypeIdentifiers

// Shown when Finder Menu.app is opened directly (Spotlight, Finder, `finder-menu settings`).
// Every change is saved right away and applies on the next right-click.
final class SettingsWindowController: NSWindowController {
    private let terminalPopup = NSPopUpButton()
    private let chooseOtherTag = 1

    convenience init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Finder Menu Settings"
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
        let version = NSTextField(labelWithString: "Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [name, version])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12

        let checkboxes = menuItems.enumerated().map { index, item in
            let box = NSButton(checkboxWithTitle: item.title, target: self, action: #selector(toggleItem(_:)))
            box.tag = index
            box.state = isHidden(item.id) ? .off : .on
            return box
        }

        terminalPopup.target = self
        terminalPopup.action = #selector(pickTerminal(_:))
        terminalPopup.isEnabled = !isHidden("terminal")
        reloadTerminalPopup()

        let note = NSTextField(labelWithString: "Changes apply the next time you right-click in Finder.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let itemsLabel = Self.sectionLabel("Show in the right-click menu")
        let terminalLabel = Self.sectionLabel("Open Terminal Here uses")
        let stack = NSStackView(views: [header, itemsLabel] + checkboxes + [terminalLabel, terminalPopup, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(10, after: itemsLabel)
        stack.setCustomSpacing(20, after: checkboxes.last!)
        stack.setCustomSpacing(10, after: terminalLabel)
        stack.setCustomSpacing(20, after: terminalPopup)
        terminalPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

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

    @objc private func toggleItem(_ sender: NSButton) {
        let item = menuItems[sender.tag]
        setHidden(item.id, sender.state == .off)
        if item.id == "terminal" { terminalPopup.isEnabled = sender.state == .on }
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
        menu.addItem(withTitle: "Automatic (\(installed.first?.name ?? "Terminal"))", action: nil, keyEquivalent: "")
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
        menu.addItem(withTitle: "Other App…", action: nil, keyEquivalent: "").tag = chooseOtherTag
        terminalPopup.menu = menu

        let selected = menu.items.first { ($0.representedObject as? String) == chosenTerminal }
        terminalPopup.select(selected ?? menu.items.first)
    }

    @objc private func pickTerminal(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == chooseOtherTag {
            let panel = NSOpenPanel()
            panel.message = "Choose the app for Open Terminal Here:"
            panel.prompt = "Choose"
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
