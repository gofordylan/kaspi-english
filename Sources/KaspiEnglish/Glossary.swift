import Foundation

/// Bundled Kaspi UI glossary (Russian + Kazakh → English). Read-only, loaded from the app bundle.
final class Glossary {
    private struct File: Decodable {
        let version: Int
        let ru: [String: String]
        let kk: [String: String]
    }

    private(set) var map: [String: String] = [:]
    /// Keys usable for in-line phrase substitution, longest first.
    private var phrases: [(key: String, value: String)] = []

    var count: Int { map.count }

    init() {
        guard let url = Glossary.locate(), let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            NSLog("KaspiEnglish: glossary.json not found or invalid")
            return
        }
        for (k, v) in file.kk { map[Glossary.normalize(k)] = v }
        for (k, v) in file.ru { map[Glossary.normalize(k)] = v } // Russian wins on collisions
        phrases = map.filter { $0.key.count >= 4 && Glossary.containsCyrillic($0.key) }
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.count > $1.key.count }
    }

    private static func locate() -> URL? {
        if let url = Bundle.main.url(forResource: "glossary", withExtension: "json") { return url }
        // `swift run` during development: look next to the package.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/glossary.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Text helpers

    private static let trimSet = CharacterSet(charactersIn: " .,:;!?…·•–—-*«»\"'()[]›>‹<|/\\")
        .union(.whitespacesAndNewlines)

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return t.trimmingCharacters(in: trimSet)
    }

    static func containsCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    /// Letters that exist in Kazakh but not Russian.
    static func looksKazakh(_ s: String) -> Bool {
        s.contains { "әіңғүұқөһӘІҢҒҮҰҚӨҺ".contains($0) }
    }

    private static func isAffixToken(_ token: Substring) -> Bool {
        !token.contains { $0.isLetter } // numbers, ₸, %, +, − …
    }

    // MARK: - Lookup

    /// Exact (normalized) match, also tolerating leading/trailing amounts like "5 000 ₸" or "12%".
    func lookup(_ text: String) -> String? {
        let n = Glossary.normalize(text)
        if let hit = map[n] { return hit }
        var tokens = n.split(separator: " ")
        var prefix: [Substring] = [], suffix: [Substring] = []
        while let first = tokens.first, Glossary.isAffixToken(first) { prefix.append(first); tokens.removeFirst() }
        while let last = tokens.last, Glossary.isAffixToken(last) { suffix.insert(last, at: 0); tokens.removeLast() }
        guard !tokens.isEmpty, !(prefix.isEmpty && suffix.isEmpty) else { return nil }
        let core = Glossary.normalize(tokens.joined(separator: " "))
        guard let hit = map[core] else { return nil }
        return (prefix.map(String.init) + [hit] + suffix.map(String.init)).joined(separator: " ")
    }

    /// Replaces any known glossary phrases inside a longer line (whole words only).
    /// Returns nil when nothing was replaced.
    func substitute(_ text: String) -> String? {
        var line = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        var lower = line.lowercased().replacingOccurrences(of: "ё", with: "е")
        guard lower.count == line.count else { return nil } // keep indices aligned
        var replaced = false
        for (key, value) in phrases {
            var searchStart = lower.startIndex
            while let r = lower.range(of: key, range: searchStart..<lower.endIndex) {
                let beforeOK = r.lowerBound == lower.startIndex || !lower[lower.index(before: r.lowerBound)].isLetter
                let afterOK = r.upperBound == lower.endIndex || !lower[r.upperBound].isLetter
                if beforeOK && afterOK {
                    let lo = line.index(line.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: r.lowerBound))
                    let hi = line.index(lo, offsetBy: key.count)
                    line.replaceSubrange(lo..<hi, with: value)
                    let llo = lower.index(lower.startIndex, offsetBy: line.distance(from: line.startIndex, to: lo))
                    lower.replaceSubrange(llo..<lower.index(llo, offsetBy: key.count), with: value.lowercased())
                    guard lower.count == line.count else { return replaced ? line : nil }
                    searchStart = lower.index(llo, offsetBy: value.count)
                    replaced = true
                } else {
                    searchStart = lower.index(after: r.lowerBound)
                }
            }
        }
        return replaced ? line : nil
    }
}
