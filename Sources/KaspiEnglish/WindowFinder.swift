import Foundation
import ScreenCaptureKit
import CoreGraphics

enum WindowFinder {
    /// Bundle identifier of /System/Applications/iPhone Mirroring.app (verified on macOS 15).
    static let mirroringBundleID = "com.apple.ScreenContinuity"
    /// Localized names used as a fallback when the bundle id doesn't match.
    static let mirroringNames = ["iphone mirroring", "повтор экрана iphone", "iphone-ды көрсету", "screencontinuity"]

    /// Normal-layer, on-screen windows of other apps that are large enough to be useful.
    static func candidateWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let myPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { w in
            w.windowLayer == 0
                && w.frame.width >= 120 && w.frame.height >= 120
                && w.owningApplication?.processID != myPID
        }
    }

    static func isMirroring(_ w: SCWindow) -> Bool {
        if w.owningApplication?.bundleIdentifier == mirroringBundleID { return true }
        let owner = (w.owningApplication?.applicationName ?? "").lowercased()
        let title = (w.title ?? "").lowercased()
        return mirroringNames.contains { owner.contains($0) || title.contains($0) }
    }

    static func findMirroring(in windows: [SCWindow]) -> SCWindow? {
        let byBundle = windows.filter { $0.owningApplication?.bundleIdentifier == mirroringBundleID }
        let pool = byBundle.isEmpty ? windows.filter(isMirroring) : byBundle
        return pool.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    static func describe(_ w: SCWindow) -> TargetWindow {
        TargetWindow(windowID: w.windowID,
                     appName: w.owningApplication?.applicationName ?? "Unknown app",
                     title: w.title ?? "",
                     bundleID: w.owningApplication?.bundleIdentifier)
    }

    /// Captures just this one window (our overlay is never included).
    static func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(max(filter.pointPixelScale, 1))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
