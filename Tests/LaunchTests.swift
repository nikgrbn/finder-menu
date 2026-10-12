import Foundation

// Go to Parent Folder puts folder paths into an AppleScript. Each name has to come back from
// AppleScript unchanged; a broken escape would turn the "x" & "y" case into "xy".
func testAppleScriptString() {
    let names = ["/plain", #"/say "hi""#, #"/back\slash"#, #"/\""#, #"/x" & "y"#, #"/\" & "y"#, "/tab\there", "/ü 😀"]
    for name in names {
        var error: NSDictionary?
        let result = NSAppleScript(source: "return " + appleScriptString(name))?.executeAndReturnError(&error)
        check(result?.stringValue == name,
              "\(name.debugDescription) came back as \(String(describing: result?.stringValue)), error: \(String(describing: error))")
    }
}

// The folder reaches the terminal whole: one argument, or one URL query value.
func testTerminalLaunch() {
    let dir = #"/Users/me/"odd" folder & co #1+2=3%"#
    for terminal in terminals {
        switch terminal.launch {
        case .openFolder:
            break
        case .arguments(let makeArguments):
            check(makeArguments(dir).contains(dir), "\(terminal.name) gets \(makeArguments(dir))")
        case .link(let makeURL):
            let url = makeURL(dir)
            let path = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "path" }?.value
            check(path == dir, "\(terminal.name) link \(String(describing: url)) carries \(String(describing: path))")
        }
    }
    // Terminal comes with macOS, so it's the fallback.
    checkEqual(terminals.last?.id, "com.apple.Terminal")
}
