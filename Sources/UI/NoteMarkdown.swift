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
            if inline.contains(.stronglyEmphasized) {
                face = NSFontManager.shared.convert(face, toHaveTrait: .boldFontMask)
                if !NSFontManager.shared.traits(of: face).contains(.boldFontMask) {
                    face = .systemFont(ofSize: face.pointSize, weight: .bold)
                }
            }
            if inline.contains(.emphasized) {
                face = NSFontManager.shared.convert(face, toHaveTrait: .italicFontMask)
                if !NSFontManager.shared.traits(of: face).contains(.italicFontMask) {
                    face = NSFontManager.shared.convert(.systemFont(ofSize: face.pointSize, weight: inline.contains(.stronglyEmphasized) ? .bold : .regular), toHaveTrait: .italicFontMask)
                }
            }
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
