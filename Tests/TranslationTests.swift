import Foundation

// Checks what's easy to miss in a translation pull request: a .strings file that doesn't parse
// (macOS then shows English everywhere), missing or extra keys, a changed %@ (String(format:) then
// shows garbage or crashes), and the language missing from CFBundleLocalizations.
func testTranslations() throws {
    let languages = try FileManager.default.contentsOfDirectory(atPath: "Resources")
        .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(".lproj".count)) }.sorted()
    check(languages.contains("en"), "no Resources/en.lproj")

    for table in ["Localizable", "InfoPlist"] {
        let english = try strings(table, "en")
        for language in languages where language != "en" {
            let file = "\(language).lproj/\(table).strings"
            let translated = try strings(table, language)
            let missing = Set(english.keys).subtracting(translated.keys).sorted()
            let extra = Set(translated.keys).subtracting(english.keys).sorted()
            check(missing.isEmpty, "\(file) is missing \(missing)")
            check(extra.isEmpty, "\(file) has keys that English doesn't: \(extra)")
            for (key, value) in translated {
                guard let original = english[key] else { continue }
                check(formatSpecifiers(value) == formatSpecifiers(original),
                      "\(file): \(value.debugDescription) needs the same format specifiers as \(original.debugDescription)")
            }
        }
    }

    // Every string the code asks for, including the menu titles it looks up by value, is in English.
    let english = try strings("Localizable", "en")
    for key in try localizedKeysInSources() + menuItems.map(\.title) {
        check(english[key] != nil, "en.lproj/Localizable.strings has no \(key.debugDescription)")
    }

    for plist in ["App-Info.plist", "Extension-Info.plist"] {
        let info = NSDictionary(contentsOfFile: "Resources/" + plist)
        let declared = (info?["CFBundleLocalizations"] as? [String] ?? []).sorted()
        checkEqual(declared, languages)
    }
}

private func strings(_ table: String, _ language: String) throws -> [String: String] {
    let path = "Resources/\(language).lproj/\(table).strings"
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let plist: Any
    do {
        plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    } catch {
        throw TestFailure(description: "\(path) doesn't parse: \(error)")
    }
    guard let strings = plist as? [String: String] else { throw TestFailure(description: "\(path) isn't a strings file") }
    return strings
}

// "%@", "%1$@", "%d"… in order of type, so a translation may reorder them with positions.
private func formatSpecifiers(_ s: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@a-zA-Z%]"#)
    return pattern.matches(in: s, range: NSRange(s.startIndex..., in: s))
        .map { (s as NSString).substring(with: $0.range).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
        .filter { $0 != "%%" }
        .sorted()
}

// The literal keys in NSLocalizedString("…") calls under Sources/.
private func localizedKeysInSources() throws -> [String] {
    let call = try NSRegularExpression(pattern: #"NSLocalizedString\("((?:[^"\\]|\\.)*)""#)
    var keys: [String] = []
    for case let file as String in FileManager.default.enumerator(atPath: "Sources")! where file.hasSuffix(".swift") {
        let source = try String(contentsOfFile: "Sources/" + file, encoding: .utf8)
        for match in call.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let literal = (source as NSString).substring(with: match.range(at: 1))
            keys.append(literal.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression))
        }
    }
    check(!keys.isEmpty, "found no NSLocalizedString calls in Sources/")
    return keys
}
