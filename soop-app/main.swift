import Cocoa
import WebKit

// main.swift — 명시적 엔트리 포인트

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
