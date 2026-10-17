import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Capture → change detection → OCR → translate, about once per second.
@MainActor
final class Pipeline {
    let state: AppState
    let glossary: Glossary
    let bridge: TranslationBridge

    /// In-memory only; cleared when the app quits.
    private var cache: [String: (english: String, origin: TranslationOrigin)] = [:]
    private var lastFingerprint: [UInt8] = []
    private var lastTargetID: CGWindowID?
    private var busy = false
    private var timer: Timer?

    /// nil = automatic (iPhone Mirroring).
    private(set) var chosenWindowID: CGWindowID?

    init(state: AppState, glossary: Glossary, bridge: TranslationBridge) {
        self.state = state
        self.glossary = glossary
        self.bridge = bridge
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick() }
    }

    func choose(windowID: CGWindowID?) {
        chosenWindowID = windowID
        forceRefresh()
    }

    func forceRefresh() {
        lastFingerprint = []
        Task { await tick() }
    }

    private func tick() async {
        guard !busy else { return }
        guard !state.paused else { state.statusText = "Paused"; return }
        guard state.overlayEnabled || state.panelVisible else { state.statusText = "Overlay hidden"; return }
        guard CGPreflightScreenCaptureAccess() else {
            state.hasScreenPermission = false
            state.statusText = "Needs Screen Recording permission"
            return
        }
        state.hasScreenPermission = true
        busy = true
        defer { busy = false }

        do {
            let windows = try await WindowFinder.candidateWindows()
            var window: SCWindow?
            if let id = chosenWindowID {
                window = windows.first { $0.windowID == id }
                if window == nil { chosenWindowID = nil } // chosen window closed → back to automatic
            }
            if window == nil { window = WindowFinder.findMirroring(in: windows) }
            guard let window else {
                if state.target != nil { state.target = nil }
                state.items = []
                state.statusText = "iPhone Mirroring window not found. Open iPhone Mirroring, or choose a window."
                return
            }
            let target = WindowFinder.describe(window)
            if state.target != target { state.target = target }
            if lastTargetID != window.windowID {
                lastTargetID = window.windowID
                lastFingerprint = []
                state.items = []
            }

            let image = try await WindowFinder.capture(window)
            let fingerprint = FrameFingerprint.make(image)
            guard FrameFingerprint.differs(fingerprint, lastFingerprint) else {
                state.statusText = "Watching \(target.displayName)"
                return
            }
            lastFingerprint = fingerprint
            state.stale = true

            let lines = try await Task.detached(priority: .userInitiated) { try OCR.recognize(image) }.value
            await translate(lines)
            state.statusText = "Watching \(target.displayName) · \(state.items.count) lines"
        } catch {
            state.statusText = "Capture failed: \(error.localizedDescription)"
        }
        state.stale = false
    }

    private func translate(_ lines: [RecognizedLine]) async {
        if cache.count > 5000 { cache.removeAll() }
        var items: [OverlayItem] = []
        var misses: [String] = []
        let appleReady = state.appleTranslation == .ready

        for (i, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Glossary.containsCyrillic(text) else { continue }
            if let hit = cache[text] {
                items.append(OverlayItem(id: i, source: text, english: hit.english, origin: hit.origin, box: line.box))
            } else if let en = glossary.lookup(text) {
                cache[text] = (en, .glossary)
                items.append(OverlayItem(id: i, source: text, english: en, origin: .glossary, box: line.box))
            } else if appleReady && !Glossary.looksKazakh(text) {
                misses.append(text)
                let interim = glossary.substitute(text) ?? text
                items.append(OverlayItem(id: i, source: text, english: interim, origin: .pending, box: line.box))
            } else if let partial = glossary.substitute(text) {
                items.append(OverlayItem(id: i, source: text, english: partial, origin: .partial, box: line.box))
            } else {
                items.append(OverlayItem(id: i, source: text, english: text, origin: .none, box: line.box))
            }
        }
        state.items = items
        state.stale = false

        guard !misses.isEmpty else { return }
        let unique = Array(Set(misses))
        let results = await bridge.translate(unique)
        for (src, en) in results where !en.isEmpty {
            cache[src] = (en, .apple)
        }
        state.items = state.items.map { item in
            guard item.origin == .pending else { return item }
            var copy = item
            if let hit = cache[item.source] {
                copy.english = hit.english
                copy.origin = hit.origin
            } else if let partial = glossary.substitute(item.source) {
                copy.english = partial
                copy.origin = .partial
            } else {
                copy.origin = .none
            }
            return copy
        }
    }
}
