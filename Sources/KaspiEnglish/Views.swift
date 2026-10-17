import AppKit
import SwiftUI
import ScreenCaptureKit

enum Brand {
    static let red = Color(red: 241 / 255, green: 70 / 255, blue: 53 / 255)
    static let disclaimer = "Unofficial helper. Not affiliated with, endorsed by, or connected to Kaspi.kz. Translations may be wrong. Always double-check amounts and recipients before confirming anything."
}

// MARK: - Side panel (Russian | English)

struct SidePanelView: View {
    @ObservedObject var state: AppState
    var onChooseWindow: () -> Void
    var onSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "character.bubble.fill").foregroundStyle(Brand.red)
                Text("Kaspi in English").font(.headline)
                Spacer()
                Button(state.paused ? "Resume" : "Pause") { state.paused.toggle() }
                Button {
                    let text = state.items.map { "\($0.source)\t\($0.english)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy all lines")
            }
            Text(state.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if state.appleTranslation != .ready {
                HStack {
                    Text(state.appleTranslation.label).font(.caption).foregroundStyle(.orange)
                    Button("Set up…", action: onSetup).controlSize(.small)
                }
            }
            if state.target == nil {
                Button("Choose a window…", action: onChooseWindow)
            }
            Divider()
            HStack {
                Text("Russian / Kazakh").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text("English").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            List(state.items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(item.source)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.english).fontWeight(.semibold).textSelection(.enabled)
                        Text(item.origin.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            Text(Brand.disclaimer).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 420)
    }
}

// MARK: - Window picker

struct WindowPickerView: View {
    var currentID: CGWindowID?
    var onPick: (CGWindowID?) -> Void
    @State private var windows: [TargetWindow] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which window should be translated?").font(.headline)
            Text("Normally this is iPhone Mirroring. Pick another window if it wasn't found automatically.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                Button { onPick(nil) } label: {
                    Label("Automatic (iPhone Mirroring)", systemImage: currentID == nil ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                ForEach(windows, id: \.windowID) { w in
                    Button { onPick(w.windowID) } label: {
                        Label(w.displayName + (w.isMirroring ? "  (iPhone Mirroring)" : ""),
                              systemImage: currentID == w.windowID ? "checkmark.circle.fill" : "macwindow")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 240)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Refresh list") { Task { await load() } }
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 460, height: 400)
        .task { await load() }
    }

    private func load() async {
        do {
            windows = try await WindowFinder.candidateWindows().map(WindowFinder.describe)
                .sorted { ($0.isMirroring ? 0 : 1, $0.appName) < ($1.isMirroring ? 0 : 1, $1.appName) }
            error = nil
        } catch {
            self.error = "Couldn't list windows: \(error.localizedDescription). Is Screen Recording allowed?"
        }
    }
}

// MARK: - First-run / setup window

struct WelcomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject var bridge: TranslationBridge
    var onRequestPermission: () -> Void
    var onOpenSettings: () -> Void
    var onRelaunch: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Kaspi in English").font(.title2.bold())
                    Text("Live English labels for the Kaspi.kz app in iPhone Mirroring")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("1. Allow Screen Recording", systemImage: state.hasScreenPermission ? "checkmark.circle.fill" : "record.circle")
                        .font(.headline)
                        .foregroundStyle(state.hasScreenPermission ? .green : .primary)
                    Text("To read the text on your mirrored iPhone, macOS requires Screen Recording permission. The app only looks at the iPhone Mirroring window, reads the text on your Mac with Apple's built-in text recognition, and keeps nothing: no screenshots, no logs, no history. It has no network access at all.")
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.hasScreenPermission {
                        HStack {
                            Button("Allow Screen Recording…", action: onRequestPermission).keyboardShortcut(.defaultAction)
                            Button("Open System Settings", action: onOpenSettings)
                            Button("Relaunch App", action: onRelaunch)
                        }
                        Text("Turn on “Kaspi in English” in System Settings → Privacy & Security → Screen & System Audio Recording, then click Relaunch App.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("2. On-device translation (optional, recommended)", systemImage: "globe").font(.headline)
                    Text("Common Kaspi buttons and menus are translated by a built-in glossary. Everything else uses Apple's on-device Translation (Russian → English).")
                        .fixedSize(horizontal: false, vertical: true)
                    TranslationSetupView(state: state, bridge: bridge)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Label("3. Use it", systemImage: "iphone").font(.headline)
                    Text("Open iPhone Mirroring, open Kaspi on the phone (set Kaspi's language to Russian for best results), and English labels appear on top.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("⌃⌥T  show/hide overlay    ⌃⌥P  Russian ↔ English side panel    ⌃⌥R  refresh")
                        .font(.system(.callout, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text(Brand.disclaimer).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done", action: onDone)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
