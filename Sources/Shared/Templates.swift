import Foundation
import Darwin

// User-defined New File templates. The extension only reads the names to build the submenu.
// The helper looks up the stored file copy by id and copies it into the folder.
// The name and contents never travel in the findermenu:// URL — only the id does.
struct FileTemplate: Equatable {
    var id = UUID().uuidString
    var filename: String
}

enum TemplateFileError: Error {
    case invalid
    case notAFile
    case duplicate(String)
}

private let templatesKey = "FileTemplates"

var fileTemplates: [FileTemplate] {
    get {
        // Decode each entry on its own, so one malformed entry doesn't hide (and later overwrite) the rest.
        (settings.array(forKey: templatesKey) ?? []).compactMap { entry in
            guard let dict = entry as? [String: Any], let id = dict["id"] as? String,
                  let filename = dict["filename"] as? String, isValidFilename(filename) else { return nil }
            return FileTemplate(id: id, filename: filename)
        }
    }
    set {
        settings.set(newValue.map { ["id": $0.id, "filename": $0.filename] }, forKey: templatesKey)
    }
}

func fileTemplate(id: String) -> FileTemplate? {
    fileTemplates.first { $0.id == id }
}

// An empty template from the New File dialog. Saving a name that's already a template keeps the existing one.
// The stored copy is an empty file; if writing it fails, the name is still saved, and creating still
// works the old way: an empty file written straight into the folder.
func saveFileTemplate(filename: String) {
    let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidFilename(name), !fileTemplates.contains(where: { $0.filename == name }) else { return }
    let template = FileTemplate(filename: name)
    do {
        let dest = try templateFileURL(id: template.id, filename: name, createDirectory: true)
        try Data().write(to: dest, options: .withoutOverwriting)
    } catch {
        NSLog("Finder Menu couldn't store an empty template: \(error)")
    }
    fileTemplates.append(template)
}

// Absolute path to a file or package that can become a template. Ordinary folders and missing paths are nil.
func templateSourceFile(atPath path: String) -> URL? {
    guard path.hasPrefix("/") else { return nil }
    let url = URL(fileURLWithPath: (path as NSString).standardizingPath).resolvingSymlinksInPath()
    do {
        try validateTemplateSource(url)
        return url
    } catch {
        return nil
    }
}

func templateSourceFile(at url: URL) -> URL? {
    templateSourceFile(atPath: url.path)
}

// A copy of an existing file or package (such as .pages). Ordinary folders are refused.
// A symlink is resolved when adding, so the store holds the file itself.
// `filename` is the template name to store (defaults to the source's last path component).
func addFileTemplate(copying source: URL, as filename: String? = nil, replace: Bool) throws {
    let name = (filename ?? source.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidFilename(name) else { throw TemplateFileError.invalid }
    let resolved = source.resolvingSymlinksInPath()
    try validateTemplateSource(resolved)

    if let existing = fileTemplates.first(where: { $0.filename == name }) {
        guard replace else { throw TemplateFileError.duplicate(name) }
        try storeTemplateCopy(id: existing.id, filename: name, from: resolved, replace: true)
        return
    }
    let template = FileTemplate(filename: name)
    try storeTemplateCopy(id: template.id, filename: name, from: resolved, replace: false)
    fileTemplates.append(template)
}

func removeFileTemplate(id: String) {
    deleteStoredTemplate(id: id)
    fileTemplates = fileTemplates.filter { $0.id != id }
}

func removeAllFileTemplates() {
    for template in fileTemplates {
        deleteStoredTemplate(id: template.id)
    }
    fileTemplates = []
}

// The file in the store for this id. nil for an old name-only template, a link, or a path outside the store.
func storedTemplateFile(_ template: FileTemplate) -> URL? {
    guard let file = try? templateFileURL(id: template.id, filename: template.filename, createDirectory: false),
          !isLink(file),
          let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey])
    else { return nil }
    if values.isDirectory == true { return values.isPackage == true ? file : nil }
    return values.isRegularFile == true ? file : nil
}

// The rules for any New File name, typed or saved as a template: no empty names, no path separators.
func isValidFilename(_ name: String) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && !name.contains("/") && name != "." && name != ".."
}

// Clears the quarantine flag on a copy without following links inside a package.
func stripQuarantine(at url: URL) {
    removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
    for case let item as URL in enumerator {
        removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        if isLink(item) { enumerator.skipDescendants() }
    }
}

// MARK: - Store

private func isSafeID(_ id: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
    return !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func isLink(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey]) else { return false }
    return values.isSymbolicLink == true || values.isAliasFile == true
}

// After resolving links, the store root must still sit inside Application Support.
private func templatesRoot(create: Bool) throws -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .resolvingSymlinksInPath()
    let root = appSupport
        .appendingPathComponent("Finder Menu", isDirectory: true)
        .appendingPathComponent("Templates", isDirectory: true)
    if create {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    let resolved = root.resolvingSymlinksInPath()
    guard resolved.path.hasPrefix(appSupport.path + "/") else { throw TemplateFileError.invalid }
    if !create {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
            throw TemplateFileError.invalid
        }
    }
    return resolved
}

private func templateFileURL(id: String, filename: String, createDirectory: Bool) throws -> URL {
    guard isSafeID(id), isValidFilename(filename) else { throw TemplateFileError.invalid }
    let root = try templatesRoot(create: createDirectory)
    let dir = root.appendingPathComponent(id, isDirectory: true)
    // A link in place of the id folder would point outside the store. deleteStoredTemplate
    // removes such a link; this path never returns a location through it.
    if isLink(dir) { throw TemplateFileError.invalid }
    if createDirectory {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    guard dir.resolvingSymlinksInPath().deletingLastPathComponent().path == root.path else {
        throw TemplateFileError.invalid
    }
    return dir.appendingPathComponent(filename)
}

private func validateTemplateSource(_ url: URL) throws {
    guard !isLink(url),
          let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey])
    else { throw TemplateFileError.notAFile }
    if values.isDirectory == true {
        guard values.isPackage == true else { throw TemplateFileError.notAFile }
        return
    }
    guard values.isRegularFile == true else { throw TemplateFileError.notAFile }
}

private func storeTemplateCopy(id: String, filename: String, from source: URL, replace: Bool) throws {
    let dest = try templateFileURL(id: id, filename: filename, createDirectory: true)
    guard !isLink(dest.deletingLastPathComponent()), !isLink(dest) else { throw TemplateFileError.invalid }
    let staging = dest.deletingLastPathComponent().appendingPathComponent("incoming-\(UUID().uuidString)")
    do {
        try FileManager.default.copyItem(at: source, to: staging)
        stripQuarantine(at: staging)
        if FileManager.default.fileExists(atPath: dest.path) {
            guard replace else { throw TemplateFileError.duplicate(filename) }
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: staging, to: dest)
    } catch {
        try? FileManager.default.removeItem(at: staging)
        throw error
    }
}

private func deleteStoredTemplate(id: String) {
    guard isSafeID(id), let root = try? templatesRoot(create: false) else { return }
    let dir = root.appendingPathComponent(id, isDirectory: true)
    guard dir.deletingLastPathComponent().resolvingSymlinksInPath().path == root.path else { return }
    guard FileManager.default.fileExists(atPath: dir.path) || isLink(dir) else { return }
    do {
        try FileManager.default.removeItem(at: dir)
    } catch {
        NSLog("Finder Menu couldn't remove a stored template: \(error)")
    }
}
