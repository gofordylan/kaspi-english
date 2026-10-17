import Foundation
import SwiftUI
import Translation

/// Bridges Apple's on-device Translation framework (macOS 15+) to the capture pipeline.
/// On macOS 15 a TranslationSession can only be obtained from SwiftUI's `.translationTask`,
/// so a host view (inside the overlay window) calls `serve(_:)` and keeps the session alive.
@MainActor
final class TranslationBridge: ObservableObject {
    static let source = Locale.Language(identifier: "ru")
    static let target = Locale.Language(identifier: "en")

    /// Non-nil only once the ru→en model is installed, so the click-through overlay never
    /// has to show the download prompt (that happens in the Setup window instead).
    @Published var configuration: TranslationSession.Configuration?

    private final class Job {
        let texts: [String]
        private var continuation: CheckedContinuation<[String: String], Never>?
        init(texts: [String], continuation: CheckedContinuation<[String: String], Never>) {
            self.texts = texts
            self.continuation = continuation
        }
        @discardableResult
        func finish(_ result: [String: String]) -> Bool {
            guard let c = continuation else { return false }
            continuation = nil
            c.resume(returning: result)
            return true
        }
    }

    private var queue: [Job] = []
    private var wakeUp: CheckedContinuation<Void, Never>?
    weak var state: AppState?

    var isServing = false

    func refreshAvailability() async {
        state?.appleTranslation = .checking
        let status = await LanguageAvailability().status(from: Self.source, to: Self.target)
        switch status {
        case .installed:
            state?.appleTranslation = .ready
            if configuration == nil {
                configuration = TranslationSession.Configuration(source: Self.source, target: Self.target)
            }
        case .supported:
            state?.appleTranslation = .needsDownload
        case .unsupported:
            state?.appleTranslation = .unsupported
        @unknown default:
            state?.appleTranslation = .unsupported
        }
    }

    /// Translates a batch of Russian strings. Returns whatever succeeded (possibly empty).
    func translate(_ texts: [String], timeout: TimeInterval = 12) async -> [String: String] {
        guard configuration != nil, !texts.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            let job = Job(texts: texts, continuation: continuation)
            queue.append(job)
            wakeUp?.resume()
            wakeUp = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self else { job.finish([:]); return }
                self.queue.removeAll { $0 === job }
                if job.finish([:]) && !self.isServing {
                    self.state?.appleTranslation = .failed("translation session didn't start")
                }
            }
        }
    }

    /// Runs inside `.translationTask`; serves queued jobs until the view goes away.
    func serve(_ session: TranslationSession) async {
        isServing = true
        defer { isServing = false }
        while !Task.isCancelled {
            guard !queue.isEmpty else {
                await withCheckedContinuation { wakeUp = $0 }
                continue
            }
            let job = queue.removeFirst()
            let requests = job.texts.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }
            do {
                let responses = try await session.translations(from: requests)
                var out: [String: String] = [:]
                for r in responses {
                    if let id = r.clientIdentifier, let i = Int(id), i < job.texts.count {
                        out[job.texts[i]] = r.targetText
                    }
                }
                job.finish(out)
            } catch {
                job.finish([:])
                state?.appleTranslation = .failed(error.localizedDescription)
            }
        }
    }
}

/// Invisible view that owns the TranslationSession for the pipeline.
struct TranslationHostView: View {
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                await bridge.serve(session)
            }
    }
}

/// Lets the user trigger the system's "download language" prompt from a normal, clickable window.
struct TranslationSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject var bridge: TranslationBridge
    @State private var setupConfig: TranslationSession.Configuration?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.appleTranslation == .ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(state.appleTranslation == .ready ? .green : .secondary)
                Text(state.appleTranslation.label)
            }
            if state.appleTranslation != .ready && state.appleTranslation != .unsupported {
                Button("Download Russian → English (on-device)…") {
                    message = "Follow the macOS prompt to download the language."
                    if setupConfig == nil {
                        setupConfig = TranslationSession.Configuration(source: TranslationBridge.source,
                                                                       target: TranslationBridge.target)
                    } else {
                        setupConfig?.invalidate()
                    }
                }
                Text("macOS downloads the language pack itself (one time). The app never uses the network. You can also add it in System Settings → General → Language & Region → Translation Languages.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .translationTask(setupConfig) { session in
            do {
                try await session.prepareTranslation()
                message = "Done."
            } catch {
                message = "Not downloaded: \(error.localizedDescription)"
            }
            await bridge.refreshAvailability()
        }
    }
}
