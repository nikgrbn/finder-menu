import Foundation

// Settings live in the helper app's preferences (local.findermenu). The settings window and
// `finder-menu terminal` write them; the sandboxed extension can only read them, through the
// shared-preference exception in Resources/Extension.entitlements.
let settingsDomain = "local.findermenu"
let settings: UserDefaults = Bundle.main.bundleIdentifier == settingsDomain
    ? .standard : UserDefaults(suiteName: settingsDomain)!

// The right-click menu's items, in menu order. The settings window lists them; the extension skips hidden ones.
let menuItems: [(id: String, title: String, symbol: String)] = [
    ("new-file", "New File…", "doc.badge.plus"),
    ("terminal", "Open Terminal Here", "terminal"),
    ("open-with", "Open Folder With", "arrow.up.forward.app"),
    ("copy-path", "Copy Path", "doc.on.doc"),
    ("parent-folder", "Go to Parent Folder", "arrow.turn.left.up"),
]

func isHidden(_ item: String) -> Bool { settings.bool(forKey: "Hide.\(item)") }

func setHidden(_ item: String, _ hidden: Bool) {
    if hidden { settings.set(true, forKey: "Hide.\(item)") } else { settings.removeObject(forKey: "Hide.\(item)") }
}

// Bundle ID of the terminal for Open Terminal Here; nil means pick the first installed one automatically.
var chosenTerminal: String? {
    get { settings.string(forKey: "Terminal") }
    set { if let newValue { settings.set(newValue, forKey: "Terminal") } else { settings.removeObject(forKey: "Terminal") } }
}

// Whether the menu also appears on drives other than the startup disk: external drives, disk images,
// network shares. On unless turned off in settings.
var showsOnOtherDrives: Bool {
    get { !settings.bool(forKey: "HideOnOtherDrives") }
    set { if newValue { settings.removeObject(forKey: "HideOnOtherDrives") } else { settings.set(true, forKey: "HideOnOtherDrives") } }
}

// The settings window posts this when showsOnOtherDrives changes. Finder only asks the extension about
// drives it already covers, so the extension can't pick up a newly allowed drive on the next right-click.
let otherDrivesChanged = Notification.Name("local.findermenu.other-drives-changed")

// Whether the menu items have icons. By default they follow Finder, whose own items have icons only since
// macOS 26. Only a choice that differs from that is saved, so an untouched Mac keeps following Finder.
var showsMenuIcons: Bool {
    get { settings.object(forKey: "MenuIcons") as? Bool ?? menuIconsByDefault }
    set { if newValue == menuIconsByDefault { settings.removeObject(forKey: "MenuIcons") } else { settings.set(newValue, forKey: "MenuIcons") } }
}

private var menuIconsByDefault: Bool {
    if #available(macOS 26, *) { return true }
    return false
}
