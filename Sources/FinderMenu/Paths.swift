import Cocoa

// Path handling for the helper's actions. Kept out of AppDelegate (and main.swift's top-level code)
// so scripts/test.sh can compile and test it.

// Only act on existing absolute paths. Files and packages such as .app bundles resolve to the
// folder that contains them.
func folder(for path: String) -> String? {
    guard path.hasPrefix("/") else { return nil }
    let path = (path as NSString).standardizingPath
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
    let dir = isDir.boolValue && !isPackage(path) ? path : (path as NSString).deletingLastPathComponent
    return isPackage(dir) ? nil : dir
}

// Checks the real location, so a symlink to an .app counts as a package too.
func isPackage(_ path: String) -> Bool {
    NSWorkspace.shared.isFilePackage(atPath: (path as NSString).resolvingSymlinksInPath)
}

// Finder-style duplicate names: "notes.md" → "notes 2.md", "notes 3.md", …
func unusedFilename(_ filename: String, in dir: String) -> String {
    let ns = filename as NSString
    let base = ns.deletingPathExtension
    let ext = ns.pathExtension
    // Unlike fileExists, attributesOfItem doesn't follow symlinks, so a broken link still counts as taken.
    func taken(_ name: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: (dir as NSString).appendingPathComponent(name))) != nil
    }
    var candidate = filename
    var n = 2
    while taken(candidate) {
        candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        n += 1
    }
    return candidate
}

// A path as an AppleScript string literal. Folder names can contain quotes and backslashes,
// and anything left unescaped would run as AppleScript.
func appleScriptString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
