import AppKit
import SwiftUI

/// Transparent, borderless, click-through, always-on-top panel that sits exactly over the mirrored iPhone.
final class OverlayWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct OverlayView: View {
    @ObservedObject var state: AppState
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                TranslationHostView(bridge: bridge)
                if state.overlayEnabled && state.windowVisible {
                    ForEach(state.items.filter { $0.english != $0.source }) { item in
                        PillLabel(item: item, canvas: geo.size)
                    }
                    .opacity(state.stale ? 0.35 : 1)
                    .animation(.easeOut(duration: 0.15), value: state.stale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }
}

struct PillLabel: View {
    let item: OverlayItem
    let canvas: CGSize

    private static let kaspiRed = Color(red: 241 / 255, green: 70 / 255, blue: 53 / 255)

    var body: some View {
        let r = CGRect(x: item.box.minX * canvas.width, y: item.box.minY * canvas.height,
                       width: item.box.width * canvas.width, height: item.box.height * canvas.height)
        let layout = Self.layout(text: item.english, rect: r, canvas: canvas)
        Text(item.english)
            .font(.system(size: layout.fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: layout.size.width, height: layout.size.height)
            .background(
                RoundedRectangle(cornerRadius: layout.size.height / 2, style: .continuous)
                    .fill(Color.black.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.size.height / 2, style: .continuous)
                    .strokeBorder(item.origin == .apple ? Color.white.opacity(0.18) : Self.kaspiRed.opacity(0.55),
                                  lineWidth: 0.75)
            )
            .offset(x: layout.origin.x, y: layout.origin.y)
            .help(item.source)
    }

    struct Layout { let fontSize: CGFloat; let size: CGSize; let origin: CGPoint }

    /// Font sized from the Russian line height; shrunk (to a floor) if the English is wider than the space available.
    static func layout(text: String, rect r: CGRect, canvas: CGSize) -> Layout {
        var fontSize = min(max(r.height * 0.78, 8), 20)
        let available = max(r.width, canvas.width - 4)
        func measure(_ size: CGFloat) -> CGFloat {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            return ceil((text as NSString).size(withAttributes: [.font: font]).width) + size * 0.9
        }
        var width = measure(fontSize)
        if width > available {
            fontSize = max(7, fontSize * available / width)
            width = min(available, measure(fontSize))
        }
        width = max(width, r.width)
        let height = max(r.height, fontSize * 1.35)
        var x = r.minX
        if x + width > canvas.width - 2 { x = max(2, canvas.width - 2 - width) }
        let y = min(max(0, r.midY - height / 2), max(0, canvas.height - height))
        return Layout(fontSize: fontSize, size: CGSize(width: width, height: height), origin: CGPoint(x: x, y: y))
    }
}

/// Keeps the overlay glued to the target window (10×/s) using the cheap CGWindowList API.
@MainActor
final class FrameTracker {
    private let state: AppState
    private let window: NSWindow
    private var timer: Timer?
    private let myPID = ProcessInfo.processInfo.processIdentifier

    init(state: AppState, window: NSWindow) {
        self.state = state
        self.window = window
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let id = state.target?.windowID,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            setVisible(false)
            return
        }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        // CoreGraphics uses a top-left origin on the primary display; AppKit uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? cg.maxY
        let frame = NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
        var visible = onScreen
        if visible && state.hideWhenCovered { visible = coveredFraction(of: id, bounds: cg) < 0.3 }
        setVisible(visible)
    }

    private func setVisible(_ visible: Bool) {
        if state.windowVisible != visible { state.windowVisible = visible }
    }

    /// Fraction of the target window hidden under other apps' normal windows.
    private func coveredFraction(of id: CGWindowID, bounds: CGRect) -> CGFloat {
        guard let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], id) as? [[String: Any]] else { return 0 }
        let area = bounds.width * bounds.height
        guard area > 0 else { return 0 }
        var covered: CGFloat = 0
        for w in above {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
            let i = b.intersection(bounds)
            if !i.isNull { covered += i.width * i.height }
        }
        return min(1, covered / area)
    }
}
