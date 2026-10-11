<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Finder Menu icon">
</p>

<h1 align="center">Finder Menu</h1>

<p align="center">Tiny Finder extension adding the right-click options macOS is missing.</p>

<p align="center">
  <img src="docs/menu.png" width="552" alt="Finder right-click menu with New File, Open Terminal Here, Open Folder With (VS Code, Sublime Text, IntelliJ IDEA, PyCharm, Xcode…), Copy Path and Go to Parent Folder">
</p>

Right-click **empty space** in any folder, with nothing selected:

| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Menu item | What it does |
|:-:|---|---|
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/new-file-dark.png"><img src="docs/icons/new-file.png" width="20" height="20" alt=""></picture> | **New&nbsp;File…** | Asks for a name with any extension (`notes.md`, `main.py`, `.env`), creates it in the current folder and selects it. Never overwrites. With [templates](#settings) configured, becomes a submenu: pick a template for one-click creation, or **Custom…** for the name dialog. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/terminal-dark.png"><img src="docs/icons/terminal.png" width="20" height="20" alt=""></picture> | **Open&nbsp;Terminal&nbsp;Here** | Opens a terminal in the current folder: iTerm2, Ghostty, Warp, WezTerm, kitty or Alacritty if you have one, otherwise Terminal. [Pick your own](#settings). |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/open-with-dark.png"><img src="docs/icons/open-with.png" width="20" height="20" alt=""></picture> | **Open&nbsp;Folder&nbsp;With&nbsp;▸** | Opens the current folder in an IDE or editor. Lists the ones you have installed (VS Code, Cursor, Windsurf, Zed, Sublime Text, JetBrains IDEs, Android Studio, Xcode…), plus **Other App…** to pick any app. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/copy-path-dark.png"><img src="docs/icons/copy-path.png" width="20" height="20" alt=""></picture> | **Copy&nbsp;Path** | Copies the current folder's full path. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/parent-folder-dark.png"><img src="docs/icons/parent-folder.png" width="20" height="20" alt=""></picture> | **Go&nbsp;to&nbsp;Parent&nbsp;Folder** | Moves the window up one level, even when Finder's Back button is greyed out (e.g. a window opened with `open .`). |

Right-clicking a file or folder works too: **Copy Path** copies the selected items' paths, and **Open Terminal Here** and **Open Folder With** use the selected folder.

## Install

**With Homebrew:**

```bash
brew install nikgrbn/tap/finder-menu
finder-menu enable
```

To update later:

```bash
brew update && brew upgrade finder-menu
finder-menu enable
```

Don't skip `brew update`: on its own, `brew upgrade` checks for new versions only once a day.

**Or from source:**

```bash
git clone https://github.com/nikgrbn/finder-menu.git
cd finder-menu
./install.sh
```

Either way, the app is built on your machine, installed to `~/Applications/Finder Menu.app` and the Finder extension is turned on. There's nothing to launch: Finder loads the extension by itself, including after a restart.

The first time you use **Go to Parent Folder**, macOS asks whether Finder Menu can control Finder. Click **OK**, because that's how it moves the window.

## Settings

<img src="docs/settings.png" width="300" align="right" alt="Finder Menu settings window: a checkbox for each right-click menu item and a picker for the terminal Open Terminal Here uses">

Open **Finder Menu** from Spotlight or your Applications folder, or run `finder-menu settings`. The settings window lets you:

- choose which items appear in the right-click menu
- pick the terminal for **Open Terminal Here**. Automatic uses the first one installed, in this order: iTerm2, Ghostty, Warp, WezTerm, kitty, Alacritty, Terminal. **Other App…** lets you pick any app.
- add **New File templates** — a filename (and optional contents) that appear under **New File** in the right-click menu. Choosing one creates the file immediately; if that name already exists, Finder Menu picks the next free name (`notes.md` → `notes 2.md`).

Changes apply the next time you right-click. You can also set the terminal from the command line: `finder-menu terminal Ghostty` (any app name works), `finder-menu terminal` to see the current choice, and `finder-menu terminal auto` to go back to automatic. If you installed from source, run `scripts/finder-menu` from the repo folder instead.

<br clear="right">

## Uninstall

With Homebrew:

```bash
finder-menu disable
brew uninstall finder-menu
```

From source:

```bash
./uninstall.sh
```

## Troubleshooting

- **Menu items don't appear:** hold ⌥, right-click Finder in the Dock and choose **Relaunch**. Also check that **Finder Menu** is turned on under System Settings → General → Login Items & Extensions → Finder extensions.
- **Asked for permission again after reinstalling:** expected. Every build is signed locally with a new signature, so macOS asks again.

## How it works

- `Sources/FinderMenuExtension` is a [Finder Sync extension](https://developer.apple.com/documentation/findersync) that adds the menu items to every folder. Finder extensions must run sandboxed, so this part only reads the clicked folder and copies paths.
- `Sources/FinderMenu` is a small helper app that isn't sandboxed and has no Dock icon. The extension hands it actions through a `findermenu://` URL, and the helper ignores those URLs from anything else. It creates the files, opens the terminal and moves the Finder window, then quits.
- `Sources/Shared/Settings.swift` holds the list of menu items and reads the settings; `Sources/FinderMenu/SettingsWindow.swift` is the settings window. The helper writes the settings, and the extension only reads them.
- `Sources/Shared/Templates.swift` holds New File templates (filename + optional contents). The extension builds the New File submenu from them; the helper looks up a template by id and never takes file contents from the URL.
- `Sources/Shared/Editors.swift` is the IDE list. The extension builds the submenu from it, and the helper refuses links naming any app that isn't on it.
- `scripts/build.sh` compiles and signs the app; `scripts/finder-menu enable|disable` copies it into `~/Applications` and turns the extension on or off. `install.sh`, `uninstall.sh` and the Homebrew formula all use these two.
- `scripts/make-icon.swift` draws the app icon in code and regenerates `Resources/AppIcon.icns` and `docs/icon.png`.

## Privacy & security

You build Finder Menu yourself from this source, so there's no downloaded app to trust. Everything below can be checked in the code:

- **No network access.** There's no networking code, so nothing is sent anywhere: no telemetry, no analytics, no update checks.
- **Small enough to read.** About 830 lines of Swift and 150 lines of shell scripts (`install.sh` and `scripts/`). Read them before you run them.
- **Sandboxed Finder extension.** It can't read your files. It only gets the folder you right-click and the items you select, plus read-only access to Finder Menu's own settings (which items to show).
- **The helper only acts when you pick a menu item.** It creates a file with the name you type or from a template you configured (never overwriting anything), opens a terminal or an app in a folder, or moves the Finder window up a level.
- **Links from other apps are ignored.** The extension sends actions to the helper as `findermenu://` links. Other apps can send those links too, and so can a website after your browser asks you. Opening a folder they choose in a terminal or IDE could run code from it, so the helper checks the code signature of whatever sent each link and ignores any that didn't come from its own Finder extension. On top of that, it only acts on folders that exist, only opens apps from its built-in IDE list (or one you pick yourself), asks before a custom New File, and for templates only uses a filename and contents you already saved in settings (never taken from the URL).
- **One permission.** Go to Parent Folder asks once to control Finder. Finder Menu doesn't ask for Full Disk Access, Accessibility or anything else.
- **Signed locally, not notarized.** `install.sh` signs the build on your Mac ("Sign to Run Locally"). It isn't notarized by Apple, because there's no download for Apple to check.

Found a security problem? See [SECURITY.md](SECURITY.md).

## License

MIT
