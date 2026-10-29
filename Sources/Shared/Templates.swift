import Foundation

// New File templates, supplied by default or saved from the New File dialog ("Save as template");
// the extension only reads them to build the New File submenu, and the helper creates the
// file from the chosen id (the file name never travels in the findermenu:// URL).
struct FileTemplate: Equatable {
    var id = UUID().uuidString
    var filename: String
}

private let templatesKey = "FileTemplates"

// Stable ids let the extension and helper agree on a preset before any preferences are saved.
let presetFileTemplates: [FileTemplate] = [
    "txt", "md", "json", "yaml", "csv", "html", "css", "js", "ts", "py", "sh",
].map { FileTemplate(id: "preset.\($0)", filename: "untitled.\($0)") }

// The extension only reads preferences. Defaults need no first-launch write from the helper.
// An explicitly saved list, including an empty one, always takes precedence over the presets.
struct FileTemplateStore {
    let preferences: UserDefaults

    var templates: [FileTemplate] {
        get {
            guard preferences.object(forKey: templatesKey) != nil else { return presetFileTemplates }
            // Decode each entry on its own, so one malformed entry doesn't hide the rest.
            return (preferences.array(forKey: templatesKey) ?? []).compactMap { entry in
                guard let dict = entry as? [String: Any], let id = dict["id"] as? String,
                      let filename = dict["filename"] as? String, isValidFilename(filename) else { return nil }
                return FileTemplate(id: id, filename: filename)
            }
        }
        nonmutating set {
            preferences.set(newValue.map { ["id": $0.id, "filename": $0.filename] }, forKey: templatesKey)
        }
    }

    // Add only missing names, keeping custom templates, order and existing ids intact.
    func restorePresets() {
        let current = templates
        let names = Set(current.map(\.filename))
        let missing = presetFileTemplates.filter { !names.contains($0.filename) }
        if !missing.isEmpty { templates = current + missing }
    }
}

private var templateStore: FileTemplateStore { FileTemplateStore(preferences: settings) }

var fileTemplates: [FileTemplate] {
    get { templateStore.templates }
    set { templateStore.templates = newValue }
}

func restorePresetFileTemplates() {
    templateStore.restorePresets()
}

func fileTemplate(id: String) -> FileTemplate? {
    fileTemplates.first { $0.id == id }
}

// Saving a name that's already a template keeps the existing one.
func saveFileTemplate(filename: String) {
    guard isValidFilename(filename), !fileTemplates.contains(where: { $0.filename == filename }) else { return }
    fileTemplates.append(FileTemplate(filename: filename))
}

func removeFileTemplate(id: String) {
    fileTemplates = fileTemplates.filter { $0.id != id }
}

// The rules for any New File name, typed or saved as a template: no empty names, no path separators.
func isValidFilename(_ name: String) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && !name.contains("/") && name != "." && name != ".."
}
