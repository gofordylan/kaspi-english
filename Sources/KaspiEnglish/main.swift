import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        Task { @MainActor in exit(await SelfTest.run()) }
        RunLoop.main.run()
    }
    // Menu-bar-only app (LSUIElement = YES in Info.plist).
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
