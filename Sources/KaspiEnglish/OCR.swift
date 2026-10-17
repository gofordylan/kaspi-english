import Foundation
import Vision
import CoreGraphics

struct RecognizedLine {
    let text: String
    /// Normalized, origin at top-left.
    let box: CGRect
}

enum OCR {
    /// ru-RU first; Kazakh only if this macOS's Vision supports it; en-US so Latin brand names (Kaspi Gold…) read cleanly.
    static let languages: [String] = {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        probe.revision = VNRecognizeTextRequestRevision3
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []
        var langs = ["ru-RU"]
        if let kk = supported.first(where: { $0.lowercased().hasPrefix("kk") }) { langs.append(kk) }
        if supported.contains("en-US") { langs.append("en-US") }
        return langs
    }()

    static func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.006
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let results = request.results ?? []
        return results.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            let b = obs.boundingBox
            return RecognizedLine(text: candidate.string,
                                  box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
    }
}

/// Tiny grayscale thumbnail used to skip OCR when the screen hasn't changed.
enum FrameFingerprint {
    static let w = 90, h = 180

    static func make(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: w * h)
        let space = CGColorSpaceCreateDeviceGray()
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buffer
    }

    static func differs(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        var total = 0
        var bigChanges = 0
        for i in 0..<a.count {
            let d = abs(Int(a[i]) - Int(b[i]))
            total += d
            if d > 28 { bigChanges += 1 }
        }
        return bigChanges > 4 || Double(total) / Double(a.count) > 1.2
    }
}
