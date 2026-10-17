import Foundation
import CoreGraphics

enum TranslationOrigin: String {
    case glossary = "Glossary"
    case apple = "Apple Translate"
    case partial = "Glossary (partial)"
    case pending = "Translating…"
    case none = "No translation"
}

struct OverlayItem: Identifiable, Equatable {
    let id: Int
    let source: String
    var english: String
    var origin: TranslationOrigin
    /// Normalized rect (0...1) in the captured window, origin at the TOP-left.
    let box: CGRect
}

struct TargetWindow: Equatable {
    let windowID: CGWindowID
    let appName: String
    let title: String
    let bundleID: String?
    var isMirroring: Bool { bundleID == WindowFinder.mirroringBundleID }
    var displayName: String { title.isEmpty || title == appName ? appName : "\(appName) — \(title)" }
}

enum AppleTranslationStatus: Equatable {
    case checking, ready, needsDownload, unsupported
    case failed(String)

    var label: String {
        switch self {
        case .checking: return "Checking Apple Translation…"
        case .ready: return "Apple Translation ready (on-device)"
        case .needsDownload: return "Russian → English language not downloaded yet"
        case .unsupported: return "Apple Translation can't translate Russian → English on this Mac"
        case .failed(let m): return "Apple Translation error: \(m)"
        }
    }
}

/// All state is in memory only. Nothing is written to disk.
@MainActor
final class AppState: ObservableObject {
    @Published var items: [OverlayItem] = []
    @Published var stale = false
    @Published var overlayEnabled = true
    @Published var panelVisible = false
    @Published var paused = false
    @Published var hideWhenCovered = true
    @Published var windowVisible = false
    @Published var target: TargetWindow?
    @Published var statusText = "Starting…"
    @Published var hasScreenPermission = CGPreflightScreenCaptureAccess()
    @Published var appleTranslation: AppleTranslationStatus = .checking
}
