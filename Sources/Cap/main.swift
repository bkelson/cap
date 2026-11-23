import AppKit

// `Cap --statusline` is the Claude Code hook: do its work and exit before any UI.
StatusLineHook.runIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
