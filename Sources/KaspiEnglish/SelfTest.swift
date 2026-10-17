import AppKit
import Translation

/// `KaspiEnglish --selftest`: renders Russian Kaspi labels, runs the real OCR + glossary path,
/// and prints the result. Used by CI to check the pipeline on a real macOS runner.
enum SelfTest {
    @MainActor
    static func run() async -> Int32 {
        let samples = ["Переводы", "Мой Банк", "Платежи", "Перевести", "Между своими счетами", "Снять наличные"]
        let size = NSSize(width: 600, height: 80 * CGFloat(samples.count))
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (i, s) in samples.enumerated() {
                (s as NSString).draw(at: NSPoint(x: 20, y: 20 + CGFloat(i) * 80),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
            }
            return true
        }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("selftest: could not render image"); return 2
        }
        let glossary = Glossary()
        print("selftest: glossary entries = \(glossary.count)")
        print("selftest: OCR languages = \(OCR.languages)")
        let lines: [RecognizedLine]
        do { lines = try OCR.recognize(cg) } catch { print("selftest: OCR failed: \(error)"); return 3 }
        var hits = 0
        for line in lines {
            let en = glossary.lookup(line.text)
            if en != nil { hits += 1 }
            print("selftest: OCR \"\(line.text)\" -> \(en ?? "(no glossary match)")")
        }
        print("selftest: lookup with amount: \(glossary.lookup("Перевести 5 000 ₸") ?? "nil")")
        print("selftest: substitute: \(glossary.substitute("Комиссия за перевод на карту другого банка") ?? "nil")")
        let status = await LanguageAvailability().status(from: TranslationBridge.source, to: TranslationBridge.target)
        print("selftest: Apple Translation ru->en status = \(status)")
        print("selftest: frame fingerprint differs from itself = \(FrameFingerprint.differs(FrameFingerprint.make(cg), FrameFingerprint.make(cg)))")
        print("selftest: \(hits)/\(samples.count) glossary hits")
        return hits >= samples.count / 2 ? 0 : 1
    }
}
