import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct NoteFile: Transferable {
    let note: Note
    static let type = UTType(filenameExtension: "md") ?? .plainText
    static let dragType = UTType(exportedAs: "com.valetivivek.margin.note-id")

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: type) { value in
            SentTransferredFile(try value.write())
        }
    }

    var filename: String {
        var title = CloudSyncEngine.safeFilename(note.title)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        while title.lowercased().hasSuffix(".md") { title.removeLast(3) }
        return (title.isEmpty ? "Untitled_note" : title) + ".md"
    }

    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Margin-Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try CloudSyncEngine.renderMarkdown(note).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func itemProvider() throws -> NSItemProvider {
        let url = try write()
        guard let provider = NSItemProvider(contentsOf: url) else { throw CocoaError(.fileReadUnknown) }
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType.identifier, visibility: .ownProcess) { completion in
            completion(Data(note.id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

enum NoteMarkdown {
    static func adding(_ trait: NSFontTraitMask, to font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        let converted = manager.convert(font, toHaveTrait: trait)
        guard !manager.traits(of: converted).contains(trait) else { return converted }
        let traits = manager.traits(of: font).union(trait)
        let fallback = NSFont.systemFont(ofSize: font.pointSize, weight: traits.contains(.boldFontMask) ? .bold : .regular)
        return traits.contains(.italicFontMask) ? manager.convert(fallback, toHaveTrait: .italicFontMask) : fallback
    }

    static func matchingFont(_ source: NSFont, sourceBaseSize: CGFloat, targetFont: NSFont) -> NSFont {
        guard source.pointSize >= 1, sourceBaseSize >= 1 else { return source }
        let size = targetFont.pointSize * source.pointSize / sourceBaseSize
        var result = NSFont(descriptor: targetFont.fontDescriptor, size: size) ?? .systemFont(ofSize: size)
        let traits = NSFontManager.shared.traits(of: source)
        if traits.contains(.boldFontMask) { result = adding(.boldFontMask, to: result) }
        if traits.contains(.italicFontMask) { result = adding(.italicFontMask, to: result) }
        return result
    }

    static func matchFonts(in text: NSMutableAttributedString, sourceBaseSize: CGFloat, targetFont: NSFont) {
        let source = NSAttributedString(attributedString: text)
        source.enumerateAttribute(.font, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard let font = value as? NSFont, font.pointSize >= 1 else { return }
            text.addAttribute(.font, value: matchingFont(font, sourceBaseSize: sourceBaseSize, targetFont: targetFont), range: range)
        }
    }

    static func normalizedRichText(_ data: Data?, matching string: String, font: NSFont, baseSize: CGFloat? = nil) -> NSMutableAttributedString? {
        guard let data,
              let source = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
              source.string == string else { return nil }
        let text = NSMutableAttributedString(attributedString: source)
        var sizes: [CGFloat: Int] = [:]
        source.enumerateAttribute(.font, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard let pointSize = (value as? NSFont)?.pointSize, pointSize >= 1 else { return }
            sizes[(pointSize * 100).rounded() / 100, default: 0] += range.length
        }
        let sourceBaseSize = baseSize.flatMap { $0 >= 1 ? $0 : nil }
            ?? sizes.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key
            ?? font.pointSize
        matchFonts(in: text, sourceBaseSize: sourceBaseSize, targetFont: font)
        return text
    }

    static func preview(_ note: Note, font: NSFont, markdown: Bool) -> AttributedString {
        if !markdown, let rich = normalizedRichText(note.presentation?.richText, matching: note.body, font: font,
                                                    baseSize: note.presentation?.richTextBaseSize.map { CGFloat($0) }) {
            let text = NSMutableAttributedString(attributedString: rich)
            var markers: [(NSRange, Bool)] = []
            (note.body as NSString).enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines]) { line, range, _, _ in
                if let line, let task = ChecklistLine.parse(line) { markers.append((NSRange(location: range.location, length: 6), task.checked)) }
            }
            text.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: text.length))
            for (range, checked) in markers.reversed() { text.replaceCharacters(in: range, with: checked ? "☑ " : "☐ ") }
            return AttributedString(text)
        }
        return markdown ? preview(note.body, font: font) : AttributedString(note.body)
    }

    static func preview(_ source: String, font: NSFont) -> AttributedString {
        let text = NSTextStorage(string: source, attributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.76)])
        let codeRanges = apply(to: text, font: font)
        var checklists: [(NSRange, Bool)] = []
        (source as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (source as NSString).length), options: [.byLines]) { line, range, _, _ in
            if let line, let task = ChecklistLine.parse(line), !codeRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                checklists.append((NSRange(location: range.location, length: 6), task.checked))
            }
        }
        for (range, checked) in checklists.reversed() {
            text.replaceCharacters(in: range, with: NSAttributedString(string: checked ? "☑ " : "☐ ", attributes: [.font: font]))
        }
        var markers: [NSRange] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont, font.pointSize < 1 { markers.append(range) }
        }
        for range in markers.reversed() { text.deleteCharacters(in: range) }
        return AttributedString(text)
    }

    // Style the source in place so editing, undo, copy and exported Markdown stay lossless.
    static func apply(to storage: NSTextStorage, font: NSFont) -> [NSRange] {
        let source = storage.string
        guard let parsed = try? AttributedString(markdown: source, options: .init(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible,
            appliesSourcePositionAttributes: true)) else { return [] }
        var codeRanges: [NSRange] = []
        var visible = IndexSet()
        var sourceCursor = 0
        for run in parsed.runs {
            guard let position = run.markdownSourcePosition,
                  let sourceRange = Range(position, in: source) else { continue }
            var range = NSRange(sourceRange, in: source)
            let content = String(parsed[run.range].characters)
            let isCodeBlock = run.presentationIntent?.components.contains {
                if case .codeBlock = $0.kind { return true }; return false
            } ?? false
            // Foundation's positions can include the list indent twice on a lazy continuation.
            if !isCodeBlock, !content.isEmpty, (source as NSString).substring(with: range) != content {
                let match = (source as NSString).range(of: content, options: .literal,
                    range: NSRange(location: sourceCursor, length: (source as NSString).length - sourceCursor))
                if match.location != NSNotFound { range = match }
            }
            sourceCursor = NSMaxRange(range)
            visible.insert(integersIn: range.location..<NSMaxRange(range))
            var attributes: [NSAttributedString.Key: Any] = [:]
            var face = font
            for component in run.presentationIntent?.components ?? [] {
                switch component.kind {
                case .header(let level):
                    face = .systemFont(ofSize: font.pointSize * [1.65, 1.4, 1.2, 1.1, 1.05, 1][min(5, max(0, level - 1))], weight: .semibold)
                case .codeBlock:
                    // Foundation includes fenced delimiters in the source range; preserve the code inside.
                    let block = (source as NSString).substring(with: range) as NSString
                    for pattern in [#"\A {0,3}(?:`{3,}|~{3,})[^\n]*(?:\n|$)"#, #"(?:^|\n) {0,3}(?:`{3,}|~{3,})[ \t]*$"#] {
                        if let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: block as String, range: NSRange(location: 0, length: block.length)) {
                            visible.remove(integersIn: (range.location + match.range.location)..<(range.location + NSMaxRange(match.range)))
                        }
                    }
                    face = .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                    attributes[.backgroundColor] = NSColor.black.withAlphaComponent(0.06)
                    codeRanges.append(range)
                case .table:
                    face = .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                case .blockQuote:
                    attributes[.foregroundColor] = NSColor.black.withAlphaComponent(0.6)
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.firstLineHeadIndent = 12; paragraph.headIndent = 12
                    attributes[.paragraphStyle] = paragraph
                default: break
                }
            }
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.stronglyEmphasized) { face = adding(.boldFontMask, to: face) }
            if inline.contains(.emphasized) { face = adding(.italicFontMask, to: face) }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if inline.contains(.code) {
                face = .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                attributes[.backgroundColor] = NSColor.black.withAlphaComponent(0.06)
                codeRanges.append(range)
            }
            if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = face
            storage.addAttributes(attributes, range: range)
        }
        // The native parser tells us exactly which source characters are rendered content.
        // Hide syntax without removing it, so undo, editing and .md exports remain lossless.
        let text = source as NSString
        for index in 0..<text.length where !visible.contains(index) && text.character(at: index) != 10 && text.character(at: index) != 13 {
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear], range: NSRange(location: index, length: 1))
        }
        return codeRanges
    }
}
