import AppKit

// Windows never restores an Explorer window on relaunch, and the macOS
// restore prompt would block startup after an unclean exit.
UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
