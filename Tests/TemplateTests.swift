import Foundation

// Exercise persistence without reading or modifying the installed app's preferences.
private func withTemplateStore(_ run: (FileTemplateStore) -> Void) {
    let domain = "local.findermenu.tests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: domain)!
    defer { preferences.removePersistentDomain(forName: domain) }
    run(FileTemplateStore(preferences: preferences))
}

func testPresetTemplates() {
    withTemplateStore { store in
        let expected = ["txt", "md", "json", "yaml", "csv", "html", "css", "js", "ts", "py", "sh"]
            .map { "untitled.\($0)" }
        checkEqual(store.templates.map(\.filename), expected)
        checkEqual(Set(store.templates.map(\.id)).count, expected.count)
        for template in store.templates {
            check(isValidFilename(template.filename), "invalid preset: \(template.filename)")
        }
        // The helper and sandboxed extension must resolve the same id independently.
        withTemplateStore { other in checkEqual(store.templates, other.templates) }
        check(store.preferences.object(forKey: "FileTemplates") == nil, "reading presets must not write preferences")
    }
}

func testSavedTemplateChoices() {
    withTemplateStore { store in
        let custom = FileTemplate(filename: "report.md")
        store.templates = [custom]
        let reopened = FileTemplateStore(preferences: store.preferences)
        checkEqual(reopened.templates, [custom])

        // Removing one preset materializes the choice, so reopening cannot bring it back.
        store.templates = presetFileTemplates.filter { $0.filename != "untitled.md" }
        check(!reopened.templates.contains(where: { $0.filename == "untitled.md" }), "removed preset reappeared")

        store.templates = []
        checkEqual(reopened.templates, [])
        check(store.preferences.object(forKey: "FileTemplates") != nil, "Remove All must save an explicit empty list")
    }
}

func testRestorePresetTemplates() {
    withTemplateStore { store in
        let custom = FileTemplate(filename: "notes.md")
        let existing = FileTemplate(filename: "untitled.txt")
        store.templates = [custom, existing]
        store.restorePresets()
        checkEqual(Array(store.templates.prefix(2)), [custom, existing])
        checkEqual(store.templates.count, presetFileTemplates.count + 1)
        checkEqual(store.templates.filter { $0.filename == "untitled.txt" }, [existing])
        checkEqual(Set(store.templates.map(\.filename)), Set(presetFileTemplates.map(\.filename) + [custom.filename]))

        let restored = store.templates
        store.restorePresets()
        checkEqual(store.templates, restored)

        store.templates = []
        store.restorePresets()
        checkEqual(store.templates, presetFileTemplates)
    }
}

func testMalformedTemplateEntries() {
    withTemplateStore { store in
        let good = FileTemplate(filename: "notes.md")
        store.preferences.set([
            ["id": good.id, "filename": good.filename],
            ["id": "invalid", "filename": "../outside.txt"],
            ["filename": "missing-id.txt"],
        ], forKey: "FileTemplates")
        checkEqual(store.templates, [good])
        store.preferences.set("not an array", forKey: "FileTemplates")
        checkEqual(store.templates, [])
    }
}
