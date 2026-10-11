import Foundation

// User-defined New File templates. The settings window writes them; the extension only reads
// them (to build the New File submenu) and the helper creates the file from the chosen id.
struct FileTemplate: Equatable {
    var id: String
    var filename: String
    var content: String

    init(id: String = UUID().uuidString, filename: String, content: String = "") {
        self.id = id
        self.filename = filename
        self.content = content
    }
}

private let templatesKey = "FileTemplates"

var fileTemplates: [FileTemplate] {
    get {
        guard let raw = settings.array(forKey: templatesKey) as? [[String: String]] else { return [] }
        return raw.compactMap { dict in
            guard let id = dict["id"], let filename = dict["filename"], isValidTemplateFilename(filename) else { return nil }
            return FileTemplate(id: id, filename: filename, content: dict["content"] ?? "")
        }
    }
    set {
        settings.set(newValue.map { ["id": $0.id, "filename": $0.filename, "content": $0.content] }, forKey: templatesKey)
    }
}

func fileTemplate(id: String) -> FileTemplate? {
    fileTemplates.first { $0.id == id }
}

// Same rules the helper uses when creating a file: no empty names, no path separators.
func isValidTemplateFilename(_ name: String) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && !name.contains("/") && name != "." && name != ".."
}
