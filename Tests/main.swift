import Foundation

// A small test runner, so the tests build with plain swiftc like the app (no Xcode project, and
// XCTest isn't part of the Command Line Tools). scripts/test.sh compiles this folder together with
// the sources it covers and runs it from the repository root.
//
// Never touch `settings` or anything that reads it (fileTemplates, isHidden, chosenTerminal…):
// outside the app bundle it is the real local.findermenu preferences.

var failures = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    guard !condition else { return }
    failures += 1
    print("  FAIL \(file):\(line): \(message())")
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) {
    check(actual == expected, "got \(actual), expected \(expected)", file: file, line: line)
}

// Thrown to stop a test that can't go on.
struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

// A new empty folder, deleted when the run ends. Standardized the way folder(for:) does it.
private var tempFolders: [String] = []
func makeTempFolder() throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FinderMenuTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    tempFolders.append(path)
    return (path as NSString).standardizingPath
}

let tests: [(name: String, run: () throws -> Void)] = [
    ("file names", testValidFilenames),
    ("unused file names", testUnusedFilename),
    ("folders from links", testFolderForLink),
    ("AppleScript strings", testAppleScriptString),
    ("terminal launch", testTerminalLaunch),
    ("translations", testTranslations),
]

for test in tests {
    let before = failures
    do {
        try test.run()
    } catch {
        failures += 1
        print("  FAIL \(error)")
    }
    print(failures == before ? "ok      \(test.name)" : "FAILED  \(test.name)")
}
for path in tempFolders { try? FileManager.default.removeItem(atPath: path) }

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
