import AppKit
import Carbon
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

extension Note {
    var displayColor: Color {
        guard let hex = presentation?.colorHex else { return color.color }
        // Keep the note surface light enough for its dark text and controls.
        let chosen = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        return Color(nsColor: chosen.blended(withFraction: 0.7, of: .white) ?? chosen)
    }
    var symbol: String { presentation?.icon.flatMap { NoteIcons.all.contains($0) ? $0 : nil } ?? "note.text" }
}

private let appPaper = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedWhite: 0.12, alpha: 1)
        : NSColor(red: 237 / 255, green: 234 / 255, blue: 227 / 255, alpha: 1)
})
private let appSidebar = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedWhite: 0.15, alpha: 1)
        : NSColor(red: 244 / 255, green: 241 / 255, blue: 234 / 255, alpha: 1)
})
private let appSearch = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedWhite: 0.20, alpha: 1)
        : NSColor(red: 227 / 255, green: 227 / 255, blue: 219 / 255, alpha: 1)
})
enum MarginPalette {
    static func accent(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 116 / 255, green: 166 / 255, blue: 255 / 255, alpha: 1)
            : NSColor(srgbRed: 54 / 255, green: 99 / 255, blue: 205 / 255, alpha: 1)
    }

    static func accentForeground(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 11 / 255, green: 20 / 255, blue: 38 / 255, alpha: 1)
            : .white
    }

    static func selectionSurface(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 38 / 255, green: 53 / 255, blue: 80 / 255, alpha: 1)
            : NSColor(srgbRed: 228 / 255, green: 236 / 255, blue: 255 / 255, alpha: 1)
    }

    static func selectionBorder(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 98 / 255, green: 134 / 255, blue: 189 / 255, alpha: 1)
            : NSColor(srgbRed: 94 / 255, green: 127 / 255, blue: 199 / 255, alpha: 1)
    }

    static let accent = NSColor(name: nil) { accent(isDark: $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
    static let accentForeground = NSColor(name: nil) { accentForeground(isDark: $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
    static let selectionSurface = NSColor(name: nil) { selectionSurface(isDark: $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
    static let selectionBorder = NSColor(name: nil) { selectionBorder(isDark: $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
}

private let appAccent = Color(nsColor: MarginPalette.accent)
private let appAccentForeground = Color(nsColor: MarginPalette.accentForeground)
private let appSelectionSurface = Color(nsColor: MarginPalette.selectionSurface)
private let appSelectionBorder = Color(nsColor: MarginPalette.selectionBorder)

private let noteFontNames = [
    "Virgil", "Caveat", "Comic Neue", "Bradley Hand", "Chalkboard SE", "Marker Felt", "Noteworthy",
    "Nunito", "Avenir Next", "American Typewriter", "Helvetica", "Cascadia Code", "Inconsolata"
].filter { NSFont(name: $0, size: 14) != nil }

extension NoteColor {
    var nsColor: NSColor {
        let base: NSColor
        switch self {
        case .amber: base = NSColor(red: 250 / 255, green: 215 / 255, blue: 111 / 255, alpha: 1)
        case .coral: base = NSColor(red: 242 / 255, green: 163 / 255, blue: 130 / 255, alpha: 1)
        case .mint: base = NSColor(red: 187 / 255, green: 225 / 255, blue: 200 / 255, alpha: 1)
        case .sky: base = NSColor(red: 176 / 255, green: 213 / 255, blue: 255 / 255, alpha: 1)
        case .lilac: base = NSColor(red: 208 / 255, green: 203 / 255, blue: 255 / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? base.blended(withFraction: 0.18, of: NSColor(calibratedWhite: 0.30, alpha: 1)) ?? base
                : base
        }
    }
    var color: Color { Color(nsColor: nsColor) }
    var name: String { String(describing: self).capitalized }
    var menuImage: NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.nsColor.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill(); return true
        }
    }
}

extension GlobalShortcut {
    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var menuKey: String {
        switch Int(keyCode) {
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Delete: return "\u{8}"
        case kVK_ForwardDelete: return String(UnicodeScalar(NSDeleteFunctionKey)!)
        case kVK_LeftArrow: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case kVK_RightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case kVK_UpArrow: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_DownArrow: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default:
            if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...20).contains(number) {
                return String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
            }
            return key.lowercased()
        }
    }
}

extension AppSettings {
    var noteFont: Font { .custom(fontName, size: textSize) }
    var listFont: Font { .custom(fontName, size: 13) }
    var nsListFont: NSFont { NSFont(name: fontName, size: 13) ?? .systemFont(ofSize: 13) }
    var nsNoteFont: NSFont { NSFont(name: fontName, size: textSize) ?? .systemFont(ofSize: textSize) }
}

private struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var lifted = false
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(colorScheme == .dark ? 0 : (lifted ? 0.24 : 0.16)), radius: lifted ? 15 : 10, x: 0, y: lifted ? 8 : 5)
    }
}

private struct SurfaceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

private func shortAge(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3_600)h" }
    return "\(seconds / 86_400)d"
}

private func agePhrase(_ date: Date) -> String {
    let age = shortAge(date)
    return age == "now" ? "now" : "\(age) ago"
}

private struct MatteButtonStyle: ButtonStyle {
    var fill: Color = .primary.opacity(0.09)
    var foreground: Color = .primary
    var width: CGFloat?
    func makeBody(configuration: Configuration) -> some View {
        MatteButtonBody(configuration: configuration, fill: fill, foreground: foreground, width: width)
    }
}

private struct MatteButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    let width: CGFloat?
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, width == nil ? 11 : 0).frame(width: width).frame(minHeight: 29)
            .contentShape(Rectangle())
            .background(fill, in: RoundedRectangle(cornerRadius: 7))
            .brightness(hovered && !configuration.isPressed ? -0.035 : 0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.10), value: hovered)
            .onHover { hovered = $0 }
    }
}

private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration)
    }
}

private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .brightness(hovered && !configuration.isPressed ? -0.05 : 0)
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.easeOut(duration: 0.10), value: hovered)
            .onHover { hovered = $0 }
    }
}

final class DragHandleNSView: NSView {
    var willDrag: (() -> Void)?
    var dragging: ((NSPoint) -> Void)?
    var didDrag: ((Bool) -> Void)?
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    private var dragStart: (frame: NSRect, pointer: NSPoint)?
    private var lastDragPointer = NSPoint.zero
    var screenPointer: (NSEvent) -> NSPoint = { _ in NSEvent.mouseLocation }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        guard willDrag != nil else { window.performDrag(with: event); return }
        dragStart = (window.frame, screenPointer(event))
        lastDragPointer = dragStart!.pointer
        NSCursor.closedHand.push()
        willDrag?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, dragStart != nil else { return }
        let pointer = screenPointer(event)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + pointer.x - lastDragPointer.x,
                                      y: window.frame.minY + pointer.y - lastDragPointer.y))
        lastDragPointer = pointer
        dragging?(pointer)
    }
    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        self.dragStart = nil
        NSCursor.pop()
        didDrag?(window?.frame != dragStart.frame)
    }
    override func draw(_ dirtyRect: NSRect) {
        if willDrag != nil {
            if hovered {
                NSColor.white.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            NSColor.white.withAlphaComponent(hovered ? 1 : 0.45).setFill()
            let dotSize: CGFloat = hovered ? 3.5 : 2.5
            for row in 0..<2 { for column in 0..<4 {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 9 + CGFloat(column) * 6 - dotSize / 2,
                                           y: bounds.midY - 2.5 + CGFloat(row) * 5 - dotSize / 2, width: dotSize, height: dotSize)).fill()
            } }
            return
        }
        NSColor.black.withAlphaComponent(hovered ? 0.7 : 0.48).setFill()
        for row in 0..<3 { for column in 0..<2 {
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3 + CGFloat(column) * 4,
                                       y: bounds.midY - 5 + CGFloat(row) * 4, width: 2, height: 2)).fill()
        } }
    }
}

struct DragHandle: NSViewRepresentable {
    var accessibilityLabel: String? = nil
    var willDrag: (() -> Void)? = nil
    var dragging: ((NSPoint) -> Void)? = nil
    var didDrag: ((Bool) -> Void)? = nil
    func makeNSView(context: Context) -> DragHandleNSView {
        let view = DragHandleNSView()
        view.setAccessibilityElement(true)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: DragHandleNSView, context: Context) {
        view.setAccessibilityLabel(accessibilityLabel ?? (willDrag == nil ? "Move note" : "Move deck"))
        view.willDrag = willDrag; view.dragging = dragging; view.didDrag = didDrag
    }
}

final class HeldCardGesture {
    private var monitor: Any?
    private var reorder: ((Int) -> Void)?
    private var finished: (() -> Void)?
    private var preciseDelta: CGFloat = 0
    private(set) var active = false
    private(set) var reordered = false

    func begin(reorder: @escaping (Int) -> Void, finished: @escaping () -> Void) {
        end()
        self.reorder = reorder; self.finished = finished
        active = true; reordered = false; preciseDelta = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseUp]) { [weak self] event in
            guard let self, self.active else { return event }
            if event.type == .scrollWheel { self.scroll(with: event); return nil }
            let consumed = self.reordered
            self.end()
            return consumed ? nil : event
        }
    }

    func scroll(with event: NSEvent) {
        guard active, event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 else { return }
        reordered = true
        let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            if preciseDelta * delta < 0 { preciseDelta = 0 }
            preciseDelta += delta
            let steps = Int(preciseDelta / 20)
            guard steps != 0 else { return }
            preciseDelta -= CGFloat(steps) * 20
            reorder?(-steps)
        } else {
            // Discrete wheel ticks must never be discarded by a time-based throttle.
            reorder?(delta > 0 ? -1 : 1)
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        active = false; reorder = nil
        let callback = finished; finished = nil
        callback?()
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

final class DeckCardInteractionView: NSView, NSDraggingSource {
    var note = Note()
    var activate: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    var holding: (Bool) -> Void = { _ in }
    var reorder: (Int) -> Void = { _ in }
    var startedDrag: () -> Void = {}
    var reportError: (String) -> Void = { _ in }
    private var tracking: NSTrackingArea?
    var gesture = HeldCardGesture()
    private var downPoint: NSPoint?
    private var downFrame = NSRect.zero
    private var exporting = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { hover(true) }
    }
    override func mouseExited(with event: NSEvent) {
        // Resizing a tracking area can emit an exit even though the pointer remains inside.
        guard !gesture.active, !bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hover(false)
    }
    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation; exporting = false
        downFrame = window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
        gesture.begin(reorder: reorder, finished: { [holding] in holding(false) })
        holding(true)
    }
    override func scrollWheel(with event: NSEvent) {
        gesture.scroll(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, gesture.active, !exporting, !gesture.reordered else { return }
        let point = NSEvent.mouseLocation
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 6,
              !downFrame.insetBy(dx: -8, dy: -8).contains(point) else { return }
        do {
            let item = NSPasteboardItem()
            item.setString(note.id.uuidString, forType: NSPasteboard.PasteboardType(NoteFile.dragType.identifier))
            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let image: NSImage
            if note.id == CalendarWing.id {
                image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar") ?? NSImage(size: NSSize(width: 40, height: 40))
            } else {
                let url = try NoteFile(note: note).write()
                item.setString(url.absoluteString, forType: .fileURL)
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
            dragItem.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: NSSize(width: 40, height: 40)),
                                      contents: image)
            exporting = true; startedDrag()
            beginDraggingSession(with: [dragItem], event: event, source: self)
        } catch { reportError(error.localizedDescription); endGesture() }
    }
    override func mouseUp(with event: NSEvent) {
        guard downPoint != nil, !exporting else { return }
        let shouldOpen = !gesture.reordered && bounds.contains(convert(event.locationInWindow, from: nil))
        endGesture()
        if shouldOpen { activate() }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        note.id == CalendarWing.id || context != .outsideApplication ? .move : .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { endGesture() }
    private func endGesture() {
        gesture.end()
        downPoint = nil; exporting = false
    }
}

private struct DeckCardInteraction: NSViewRepresentable {
    let note: Note
    let gesture: HeldCardGesture
    let activate: () -> Void
    let hover: (Bool) -> Void
    let holding: (Bool) -> Void
    let reorder: (Int) -> Void
    let startedDrag: () -> Void
    let error: (String) -> Void
    func makeNSView(context: Context) -> DeckCardInteractionView { let view = DeckCardInteractionView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: DeckCardInteractionView, context: Context) {
        view.note = note; view.gesture = gesture; view.activate = activate; view.hover = hover; view.holding = holding
        view.reorder = reorder; view.startedDrag = startedDrag; view.reportError = error
    }
}

private struct ChecklistPreviewLine: View {
    let line: String
    let font: NSFont
    private var checkboxSize: CGFloat { ChecklistMarkGeometry.boxSize(font: font) }

    var body: some View {
        if let item = ChecklistLine.parse(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RoundedRectangle(cornerRadius: checkboxSize / 4)
                    .fill(item.checked ? Color.black.opacity(0.48) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: checkboxSize / 4).stroke(.black.opacity(0.36), lineWidth: 1.2))
                    .overlay { if item.checked { Image(systemName: "checkmark").font(.system(size: checkboxSize * 0.6, weight: .bold)).foregroundStyle(.white) } }
                    .frame(width: checkboxSize, height: checkboxSize)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + ChecklistMarkGeometry.baselineOffset(font: font) }
                Text(item.text.isEmpty ? " " : item.text).foregroundStyle(.black.opacity(item.checked ? 0.44 : 0.72)).strikethrough(item.checked)
            }.font(Font(font))
        } else {
            Text(line.isEmpty ? " " : line).font(Font(font))
        }
    }
}

struct EdgeDeckView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: EdgePanelModel
    let expand: (Bool) -> Void
    let hover: (Bool) -> Bool
    let beginDrag: () -> Void
    let draggingDeck: (NSPoint) -> Void
    let endDrag: (Bool) -> Void
    let create: () -> Void
    let open: (UUID) -> Void
    let showAll: () -> Void
    let showArchive: () -> Void
    let showSettings: () -> Void
    @State private var hovered: UUID?
    @State private var dragging: UUID?
    @State private var hoverReadyAt = 0.0
    @State private var plusHovered = false

    private var deckItems: [Note] { CalendarWing.items(notes: store.active, enabled: settings.calendarEnabled, position: settings.calendarPosition, limit: model.noteLimit, color: settings.calendarColor) }
    private var collapsedDeckItems: [Note] { deckItems.filter { $0.id != CalendarWing.id } }

    var body: some View {
        ZStack(alignment: model.side == .bottom ? .bottom : (model.side == .right ? .trailing : .leading)) {
            Color.clear
            if deckItems.isEmpty {
                deckAddButton.contextMenu { deckMenu }
            } else if model.side == .bottom {
                if model.expanded || settings.keepOpen { bottomFan } else { bottomPill }
            } else if model.expanded || settings.keepOpen {
                fan
            } else {
                pill
            }
            if let undo = store.undoNote, !deckItems.isEmpty {
                HStack(spacing: 8) {
                    Text("\(undo.title) deleted").lineLimit(1)
                    Button("Undo") { store.undoDelete() }.buttonStyle(.borderless).fontWeight(.semibold)
                }
                .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule()).shadow(radius: 8)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
            }
        }
    }

    private var bottomPill: some View {
        Button { expand(true) } label: {
            HStack(spacing: 6) {
                ForEach(collapsedDeckItems) { note in
                    Capsule().fill(note.displayColor).frame(width: 16, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.48), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { _ = hover($0) }
        .contextMenu { deckMenu }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("Show Margin deck")
    }

    private var bottomFan: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(deckItems.enumerated()), id: \.element.id) { index, note in
                if note.id == CalendarWing.id { calendarSlot(index: index) }
                else {
                    bottomSlot(note, index: index)
                        .onDrop(of: [NoteFile.dragType], delegate: NoteDropDelegate(target: note.id, dragging: $dragging, store: store, settings: settings, side: model.side))
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { deckControls.offset(x: 72) }
        .padding(.horizontal, 80).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { inside in
            if !hover(inside) { hovered = nil }
        }
        .onAppear { hovered = nil; hoverReadyAt = ProcessInfo.processInfo.systemUptime + settings.fanDuration }
        .onDisappear { hovered = nil }
    }

    private func bottomSlot(_ note: Note, index: Int) -> some View {
        let current = store.note(note.id) ?? note
        let lifted = hovered == note.id
        return Button { activate(note, lifted: lifted) } label: {
            ZStack(alignment: .bottom) {
                if lifted {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(current.title, systemImage: current.symbol).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(NoteMarkdown.preview(current, font: settings.nsNoteFont, markdown: settings.markdownEnabled))
                            .lineLimit(4)
                        Spacer(minLength: 0)
                    }
                    .font(settings.noteFont).foregroundStyle(.black.opacity(0.72))
                    .padding(12).frame(width: DeckCardMetrics.contentWidth, height: DeckCardMetrics.height, alignment: .topLeading)
                    .background(current.displayColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .modifier(CardShadow(lifted: true))
                    .padding(.bottom, 34)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                Text(current.title.isEmpty ? "Untitled note" : current.title)
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(.black.opacity(0.66)).padding(.horizontal, 9)
                    .frame(width: DeckCardMetrics.bottomStep - 7, height: 30)
                    .background(current.displayColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .offset(y: lifted ? -8 : 0)
        .frame(width: DeckCardMetrics.bottomStep, height: 210, alignment: .bottom)
        .overlay(alignment: .bottom) {
            cardInteraction(note, lifted: lifted)
                .frame(width: lifted ? DeckCardMetrics.contentWidth : DeckCardMetrics.bottomStep, height: 210)
                .transaction { $0.animation = nil }
            }
        .contextMenu { if note.id == CalendarWing.id { Button("Open Calendar") { open(note.id) }; Button("Settings…", action: showSettings) } else { noteMenu(current) } }
        .zIndex(lifted ? 20 : Double(index))
        .animation(reduceMotion || model.dragging ? nil : .easeOut(duration: settings.animationDuration), value: lifted)
        .help(current.title)
        .accessibilityLabel("\(current.title), \(current.color.name)")
    }

    private var pill: some View {
        VStack(spacing: 5) {
            if deckItems.isEmpty {
                Button(action: create) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Add note")
            } else {
                Button { expand(true) } label: {
                    VStack(spacing: 6) {
                        ForEach(collapsedDeckItems) { note in
                            Capsule().fill(note.displayColor).frame(width: 6, height: 16)
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 9)
                    .background(.black.opacity(0.48), in: Capsule())
                    .shadow(color: .black.opacity(0.24), radius: 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { _ = hover($0) }
                .contextMenu { deckMenu }
                .accessibilityLabel("Show Margin deck")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.side == .right ? .trailing : .leading)
    }

    private var fan: some View {
        let notes = deckItems
        let edge: Alignment = model.side == .right ? .trailing : .leading
        return ZStack(alignment: edge) {
            VStack(spacing: DeckCardMetrics.spacing) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    if note.id == CalendarWing.id { calendarSlot(index: index) }
                    else {
                        deckCard(note, index: index)
                            .onDrop(of: [NoteFile.dragType], delegate: NoteDropDelegate(target: note.id, dragging: $dragging, store: store, settings: settings, side: model.side))
                    }
                }
            }
            .frame(height: DeckCardMetrics.stackHeight(count: notes.count))
            deckControls
                .offset(y: notes.isEmpty ? 0 : DeckCardMetrics.stackHeight(count: notes.count) / 2 + 28)
                .opacity(model.fanVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
        .contentShape(Rectangle())
        .onHover { inside in
            if !hover(inside) { hovered = nil }
        }
        .onAppear { hovered = nil; hoverReadyAt = ProcessInfo.processInfo.systemUptime + settings.fanDuration }
        .onDisappear { hovered = nil }
    }

    private var deckControls: some View {
        VStack(spacing: 2) {
            deckAddButton
            DragHandle(willDrag: beginDrag, dragging: draggingDeck, didDrag: endDrag)
                .frame(width: 36, height: 22)
                .help("Drag to the left, right or bottom edge. Release elsewhere to return to the previous position.")
        }
        .overlay(alignment: .top) {
            if store.active.count > model.noteLimit - (settings.calendarEnabled ? 1 : 0) {
                Button("+\(store.active.count - model.noteLimit + (settings.calendarEnabled ? 1 : 0)) more") { showAll() }
                    .buttonStyle(.borderless).fixedSize()
                    .offset(x: model.side == .bottom ? 0 : (model.side == .left ? 60 : -60), y: model.side == .bottom ? -24 : 0)
                    .help("Show all notes")
            }
        }
    }

    private var deckAddButton: some View {
        Button { expand(true); create() } label: {
            ZStack {
                Circle().fill(.black.opacity(plusHovered ? 0.34 : 0.48))
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(plusHovered ? 0.96 : 0.72))
            }
            .frame(width: 31, height: 31)
            .scaleEffect(reduceMotion ? 1 : (plusHovered ? 1 : 0.92))
            .rotationEffect(.degrees(reduceMotion ? 0 : (plusHovered ? 180 : 0)))
            .shadow(color: .black.opacity(plusHovered ? 0.20 : 0.10), radius: plusHovered ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain).frame(width: 40, height: 40).contentShape(Circle())
        .onHover { plusHovered = $0; if $0 { expand(true) } }
        .animation(reduceMotion || model.dragging ? nil : .timingCurve(0.20, 1.00, 0.30, 1.00, duration: 0.20 * settings.animationScale), value: plusHovered)
        .zIndex(20)
        .accessibilityLabel("Add")
    }

    private func calendarSlot(index: Int) -> some View {
        Button { open(CalendarWing.id) } label: {
            VStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 15, weight: .medium))
                if model.side != .bottom { Text(Date().formatted(.dateTime.day())).font(.system(size: 13, weight: .semibold)) }
            }
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: model.side == .bottom ? DeckCardMetrics.bottomStep - 7 : 34,
                   height: model.side == .bottom ? 30 : DeckCardMetrics.height)
            .background(settings.calendarColor.color, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: model.side == .bottom ? DeckCardMetrics.bottomStep : DeckCardMetrics.visibleWidth,
               height: model.side == .bottom ? 210 : DeckCardMetrics.height,
               alignment: model.side == .bottom ? .bottom : model.side == .right ? .trailing : .leading)
        .overlay(alignment: model.side == .bottom ? .bottom : model.side == .right ? .trailing : .leading) {
            cardInteraction(CalendarWing.item(color: settings.calendarColor), lifted: false)
                .frame(width: model.side == .bottom ? DeckCardMetrics.bottomStep : 34,
                       height: model.side == .bottom ? 30 : DeckCardMetrics.height)
                .transaction { $0.animation = nil }
        }
        .opacity(model.fanVisible ? 1 : 0)
        .zIndex(Double(index))
        .contextMenu { Button("Open Calendar") { open(CalendarWing.id) }; Button("Calendar Settings…", action: showSettings) }
        .accessibilityLabel("Calendar").help("Click to open the month calendar")
    }

    private func deckCard(_ note: Note, index: Int) -> some View {
        let current = store.note(note.id) ?? note
        let lifted = hovered == note.id
        let activeOffset = lifted ? DeckCardMetrics.liftedOffset : DeckCardMetrics.tuckedOffset(index: index)
        let offset = reduceMotion || model.fanVisible ? activeOffset : DeckCardMetrics.hiddenOffset
        let isLast = index == deckItems.count - 1
        let edge: Alignment = model.side == .right ? .trailing : .leading
        return Button { activate(note, lifted: lifted) } label: {
            ZStack(alignment: edge) {
                HStack(spacing: 0) {
                if model.side == .right { tabLabel(current.title) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if model.side == .right {
                            Label(current.title, systemImage: current.symbol).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(shortAge(current.updatedAt)).font(.system(size: 9)).foregroundStyle(.black.opacity(0.42))
                        } else {
                            Text(shortAge(current.updatedAt)).font(.system(size: 9)).foregroundStyle(.black.opacity(0.42))
                            Spacer(minLength: 0)
                            Label(current.title, systemImage: current.symbol).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NoteMarkdown.preview(current, font: settings.nsNoteFont, markdown: settings.markdownEnabled))
                            .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(settings.noteFont).foregroundStyle(.black.opacity(0.72))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(width: DeckCardMetrics.contentWidth, height: DeckCardMetrics.height, alignment: .topLeading)
                if model.side == .left { tabLabel(current.title) }
            }
            .frame(width: DeckCardMetrics.width, height: DeckCardMetrics.height)
            .foregroundStyle(.black.opacity(0.73))
            .background(current.displayColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(CardShadow(lifted: lifted))
            .rotationEffect(.degrees(model.side == .right ? -2.2 : 2.2))
            .offset(x: model.side == .right ? offset : -offset)
            .opacity(model.fanVisible ? 1 : (reduceMotion ? 0 : 1))
                .animation(reduceMotion || model.dragging ? nil : .easeOut(duration: settings.animationDuration), value: lifted)
                .animation(reduceMotion || model.dragging ? nil : .easeOut(duration: settings.animationDuration), value: model.fanVisible)
            }
        }
        .buttonStyle(.plain)
        .frame(width: DeckCardMetrics.visibleWidth, height: DeckCardMetrics.height, alignment: edge)
        .overlay(alignment: model.side == .right ? .topTrailing : .topLeading) {
            cardInteraction(note, lifted: lifted)
                .frame(width: DeckCardMetrics.hoverWidth(lifted: lifted, index: index),
                       height: DeckCardMetrics.hoverHeight(lifted: lifted, isLast: isLast))
                .transaction { $0.animation = nil }
        }
        .zIndex(Double(index))
        .contextMenu { if note.id == CalendarWing.id { Button("Open Calendar") { open(note.id) }; Button("Settings…", action: showSettings) } else { noteMenu(current) } }
        .help(current.title)
        .accessibilityLabel("\(current.title), \(current.color.name), edited \(current.updatedAt.formatted(date: .omitted, time: .shortened))")
    }

    private func activate(_ note: Note, lifted: Bool) {
        if DeckHoverGate.opensOnTap(mode: settings.fanMode, alreadyPreviewed: lifted) { open(note.id) }
        else { hovered = note.id }
    }

    private func cardInteraction(_ note: Note, lifted: Bool) -> some View {
        DeckCardInteraction(note: store.note(note.id) ?? note, gesture: model.cardGesture,
            activate: { note.id == CalendarWing.id ? open(note.id) : activate(note, lifted: lifted) },
            hover: { inside in
                guard model.reorderingNote == nil else { return }
                guard note.id != CalendarWing.id else { return }
                if inside && settings.fanMode == .hover && DeckHoverGate.isReady(now: ProcessInfo.processInfo.systemUptime, readyAt: hoverReadyAt) { hovered = note.id }
                if !inside && settings.fanMode == .hover && hovered == note.id { hovered = nil }
            },
            holding: { model.reorderingNote = $0 ? note.id : nil },
            reorder: { step in
                if note.id == CalendarWing.id {
                    settings.calendarPosition = CalendarWing.movedPosition(settings.calendarPosition, by: step, noteCount: store.active.count, limit: model.noteLimit)
                } else { store.move(note.id, by: step) }
            },
            startedDrag: { dragging = note.id },
            error: { store.errorMessage = $0 })
    }

    private func tabLabel(_ title: String) -> some View {
        Text(title.isEmpty ? "Untitled note" : title)
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.58))
            .lineLimit(1).truncationMode(.tail)
            .frame(width: DeckCardMetrics.height - 28)
            .rotationEffect(.degrees(model.side == .right ? -90 : 90))
            .frame(width: DeckCardMetrics.tabWidth, height: DeckCardMetrics.height - 20)
            .padding(.top, 10).frame(width: DeckCardMetrics.tabWidth, height: DeckCardMetrics.height, alignment: .top)
            .overlay(alignment: model.side == .right ? .trailing : .leading) {
                Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: DeckCardMetrics.height - 24)) }
                    .stroke(.black.opacity(0.36), style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    .frame(width: 1, height: DeckCardMetrics.height - 24).padding(.vertical, 12)
            }
    }

    @ViewBuilder private func noteMenu(_ note: Note) -> some View {
        Menu { ForEach(NoteColor.allCases, id: \.rawValue) { value in
            Button { var copy = note; copy.color = value; copy.presentation?.colorHex = nil; store.update(copy, immediate: true) } label: {
                HStack { Image(nsImage: value.menuImage); Text(value.name); if note.color == value && note.presentation?.colorHex == nil { Image(systemName: "checkmark") } }
            }
        } } label: { Label("Color", systemImage: "paintpalette") }
        Button { var copy = note; copy.pinned.toggle(); store.update(copy, immediate: true); if copy.pinned { open(copy.id) } } label: {
            Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
        }
        Button { if let copy = store.duplicate(note.id) { open(copy.id) } } label: { Label("Duplicate", systemImage: "doc.on.doc") }
        Menu {
            Button { model.side = .left } label: { Label("Left", systemImage: "rectangle.lefthalf.inset.filled") }
            Button { model.side = .right } label: { Label("Right", systemImage: "rectangle.righthalf.inset.filled") }
            Button { model.side = .bottom } label: { Label("Bottom", systemImage: "rectangle.bottomhalf.inset.filled") }
        } label: { Label("Screen Side", systemImage: "rectangle.split.3x1") }
        Divider()
        Button(action: showAll) { Label("All Notes…", systemImage: "square.grid.2x2") }
        Button(action: showArchive) { Label("Show Archive…", systemImage: "archivebox") }
        Button(action: showSettings) { Label("Settings…", systemImage: "gearshape") }
        Divider()
        Button(role: .destructive) { store.delete(note.id) } label: { Label("Delete", systemImage: "trash") }
        Button { NSApp.terminate(nil) } label: { Label("Quit Margin", systemImage: "power") }
    }

    @ViewBuilder private var deckMenu: some View {
        Button(action: create) { Label("New Note", systemImage: "square.and.pencil") }
        Button(action: showAll) { Label("All Notes…", systemImage: "square.grid.2x2") }
        Button(action: showArchive) { Label("Show Archive…", systemImage: "archivebox") }
        Button(action: showSettings) { Label("Settings…", systemImage: "gearshape") }
        Divider()
        Menu("Screen Side") {
            Button("Left") { model.side = .left }
            Button("Right") { model.side = .right }
            Button("Bottom") { model.side = .bottom }
        }
        Menu("Font") {
            ForEach(noteFontNames, id: \.self) { value in
                Button { settings.fontName = value } label: { Text(value).font(.custom(value, size: 14)) }
            }
        }
        Menu("Font Size") {
            ForEach([10.0, 12.0, 14.0, 16.0, 18.0, 21.0, 24.0, 28.0], id: \.self) { value in Button("\(Int(value)) pt") { settings.textSize = value } }
        }
        Menu("Animation Speed") {
            Button("Fast") { settings.animationSpeed = .fast }
            Button("Normal") { settings.animationSpeed = .normal }
            Button("Slow") { settings.animationSpeed = .slow }
        }
        Divider()
        Toggle("Show Over Full-Screen Apps", isOn: $settings.showOverFullScreen)
        Toggle("Lock Notes", isOn: $settings.lockNotes)
        Button { ExportController.export(.markdown, notes: store.notes, store: store) } label: { Label("Export Notes…", systemImage: "square.and.arrow.up") }
        Divider()
        Button { NSApp.terminate(nil) } label: { Label("Quit Margin", systemImage: "power") }
    }
}

enum DeckHoverGate {
    static func isReady(now: Double, readyAt: Double) -> Bool { now >= readyAt }
    static func opensOnTap(mode: FanMode, alreadyPreviewed: Bool) -> Bool { mode == .hover || alreadyPreviewed }
}

enum DeckCardMetrics {
    static let width: CGFloat = 216
    static let contentWidth: CGFloat = 182
    static let visibleWidth: CGFloat = 182
    static let height: CGFloat = 152
    static let step: CGFloat = 68
    static let spacing = step - height
    static let tabWidth: CGFloat = 34
    static let liftedOffset = width - visibleWidth
    static let hiddenOffset = width - 6
    static let bottomStep: CGFloat = 104

    static func stackHeight(count: Int) -> CGFloat { count == 0 ? 0 : height + CGFloat(count - 1) * step }

    static func tuckedOffset(index: Int) -> CGFloat { width - tabWidth - CGFloat(index * 4) }
    static func hoverWidth(lifted: Bool, index: Int) -> CGFloat { lifted ? visibleWidth : tabWidth + CGFloat(index * 4) }
    static func hoverHeight(lifted: Bool, isLast: Bool) -> CGFloat { lifted || isLast ? height : step }
}

private struct NoteDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let store: NotesStore
    let settings: AppSettings
    let side: ScreenSide
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        if dragging == CalendarWing.id, let targetIndex = store.active.firstIndex(where: { $0.id == target }) {
            let after = side == .bottom ? info.location.x > DeckCardMetrics.bottomStep / 2 : info.location.y > DeckCardMetrics.height / 2
            settings.calendarPosition = targetIndex + (after ? 1 : 0)
        } else if target != CalendarWing.id { store.move(dragging, before: target) }
    }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

final class ChecklistNSTextView: NSTextView {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    var changed: ((String) -> Void)?
    var richChanged: ((Data?) -> Void)?
    var cancelled: (() -> Void)?
    var noteFont: NSFont = .systemFont(ofSize: 21) {
        didSet {
            guard hasRichFormatting,
                  oldValue.fontName != noteFont.fontName || oldValue.pointSize != noteFont.pointSize,
                  let storage = textStorage else { return }
            NoteMarkdown.matchFonts(in: storage, sourceBaseSize: oldValue.pointSize, targetFont: noteFont)
            if let font = typingAttributes[.font] as? NSFont {
                typingAttributes[.font] = NoteMarkdown.matchingFont(font, sourceBaseSize: oldValue.pointSize, targetFont: noteFont)
            }
        }
    }
    var markdownEnabled = false {
        didSet {
            if oldValue != markdownEnabled {
                hasRichFormatting = false
                textStorage?.setAttributes(normalTypingAttributes, range: NSRange(location: 0, length: (string as NSString).length))
            }
        }
    }
    private var hasRichFormatting = false
    private var codeRanges: [NSRange] = []
    var previewDelay: Double = 5
    private(set) var isPreview = true
    private var previewTimer: Timer?
    private var pointerTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); pointerTracking = area
    }

    override func mouseExited(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        showPreview()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { showPreview() }
        return resigned
    }

    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with: event)
    }

    deinit { previewTimer?.invalidate() }

    func beginSourceEditing() {
        if markdownEnabled && isPreview {
            isPreview = false
            applyStyle()
        }
        schedulePreview()
    }

    private func schedulePreview() {
        previewTimer?.invalidate()
        guard markdownEnabled, !isPreview, window != nil else { return }
        let timer = Timer(timeInterval: previewDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.hasMarkedText() || self.selectedRange().length > 0 || NSEvent.pressedMouseButtons != 0 {
                self.schedulePreview()
            } else { self.showPreview() }
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func showPreview() {
        previewTimer?.invalidate(); previewTimer = nil
        guard markdownEnabled, !hasMarkedText() else { return }
        isPreview = true
        applyStyle()
        needsDisplay = true
    }


    override func didChangeText() {
        super.didChangeText()
        if markdownEnabled { beginSourceEditing() } else { hasRichFormatting = true }
        applyStyle()
        changed?(string)
        richChanged?(markdownEnabled ? nil : richData())
        needsDisplay = true
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        beginSourceEditing()
        let value = (insertString as? NSAttributedString)?.string ?? insertString as? String
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if value == "]", range.length == 0,
           let shortcut = Self.checklistShortcutRange(in: string, before: range.location) {
            super.insertText("- [ ] ", replacementRange: shortcut)
            return
        }
        if value == " ", range.length == 0, range.location > 0 {
            let text = string as NSString
            let line = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            if text.substring(with: NSRange(location: line.location, length: range.location - line.location)) == "-" {
                super.insertText("• ", replacementRange: NSRange(location: line.location, length: 1))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    static func checklistShortcutRange(in text: String, before cursor: Int) -> NSRange? {
        let value = text as NSString
        guard cursor > 0, cursor <= value.length,
              value.substring(with: NSRange(location: cursor - 1, length: 1)) == "[" else { return nil }
        let line = value.lineRange(for: NSRange(location: cursor - 1, length: 0))
        let leading = NSRange(location: line.location, length: cursor - line.location - 1)
        guard value.substring(with: leading).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return NSRange(location: cursor - 1, length: 1)
    }

    static func links(in text: String) -> [(URL, NSRange)] {
        linkDetector?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).compactMap { match in
            guard let url = match.url else { return nil }
            return (url, match.range)
        } ?? []
    }

    static func opensLink(with modifiers: NSEvent.ModifierFlags, keyHeld: Bool = false) -> Bool {
        !keyHeld && modifiers.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }

    private var normalTypingAttributes: [NSAttributedString.Key: Any] {
        [.font: noteFont, .foregroundColor: NSColor.black]
    }

    func applyStyle() {
        usesAdaptiveColorMappingForDarkAppearance = false
        appearance = NSAppearance(named: .aqua)
        guard let storage = textStorage else { return }
        let selection = selectedRanges
        selectedTextAttributes = [
            .backgroundColor: NSColor.black.withAlphaComponent(0.14),
            .foregroundColor: NSColor.black.withAlphaComponent(0.88)
        ]
        storage.beginEditing()
        let priorTyping = typingAttributes
        if markdownEnabled || !hasRichFormatting {
            storage.setAttributes(normalTypingAttributes, range: NSRange(location: 0, length: storage.length))
        } else {
            storage.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: storage.length))
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if (value as? NSFont)?.pointSize ?? 0 < 1 { storage.addAttributes(self.normalTypingAttributes, range: range) }
            }
        }
        storage.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: storage.length))
        if markdownEnabled && !isPreview {
            codeRanges = []
            (string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: storage.length), options: [.byLines]) { line, range, _, _ in
                guard let line else { return }
                let prefix = ChecklistLine.parse(line) != nil ? String(line.prefix(6)) : line.hasPrefix("• ") ? "• " : line.hasPrefix("- ") ? "- " : ""
                guard !prefix.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle()
                paragraph.headIndent = (prefix as NSString).size(withAttributes: [.font: self.noteFont]).width
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
            storage.endEditing(); selectedRanges = selection
            typingAttributes = normalTypingAttributes
            insertionPointColor = NSColor.black
            needsDisplay = true
            return
        }
        codeRanges = markdownEnabled ? NoteMarkdown.apply(to: storage, font: noteFont) : []
        (string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (string as NSString).length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard !self.codeRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
            if (self.string as NSString).substring(with: range).hasPrefix("• ") {
                let paragraph = NSMutableParagraphStyle()
                let bodyFont = range.length > 2 ? (storage.attribute(.font, at: range.location + 2, effectiveRange: nil) as? NSFont ?? self.noteFont) : self.noteFont
                storage.addAttributes([.font: NSFont.systemFont(ofSize: bodyFont.pointSize * 1.3, weight: .bold),
                                       .baselineOffset: -bodyFont.pointSize * 0.06], range: NSRange(location: range.location, length: 1))
                paragraph.headIndent = storage.attributedSubstring(from: NSRange(location: range.location, length: 2)).size().width
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
            if range.length >= 6 {
                let prefix = (self.string as NSString).substring(with: NSRange(location: range.location, length: 6)).lowercased()
                if prefix == "- [ ] " || prefix == "- [x] " {
                    let marker = NSRange(location: range.location, length: 6)
                    let paragraph = NSMutableParagraphStyle()
                    let taskFont = self.taskFont(at: range.location)
                    let indent = ChecklistMarkGeometry.boxSize(font: taskFont) + 8
                    paragraph.firstLineHeadIndent = indent; paragraph.headIndent = indent
                    paragraph.minimumLineHeight = self.layoutManager?.defaultLineHeight(for: self.noteFont)
                        ?? ceil(self.noteFont.ascender - self.noteFont.descender + self.noteFont.leading)
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)], range: marker)
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                    if !self.markdownEnabled, range.length > 6 {
                        let body = NSRange(location: range.location + 6, length: range.length - 6)
                        storage.removeAttribute(.strikethroughStyle, range: body)
                        storage.addAttribute(.foregroundColor, value: NSColor.black, range: body)
                    }
                    if prefix == "- [x] ", range.length > 6 {
                        let body = NSRange(location: range.location + 6, length: range.length - 6)
                        let value = (self.string as NSString).substring(with: body)
                        var visible = body
                        if value.hasPrefix("~~"), value.hasSuffix("~~"), value.count >= 4 {
                            let opening = NSRange(location: body.location, length: 2)
                            let closing = NSRange(location: NSMaxRange(body) - 2, length: 2)
                            storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)], range: opening)
                            storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)], range: closing)
                            visible = NSRange(location: body.location + 2, length: body.length - 4)
                        }
                        storage.addAttributes([
                            .foregroundColor: NSColor.black.withAlphaComponent(0.45),
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue
                        ], range: visible)
                    }
                }
            }
        }
        for (url, range) in Self.links(in: string) where
            (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 > 1
            && !codeRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            storage.addAttributes([.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
        }
        storage.endEditing(); selectedRanges = selection
        typingAttributes = markdownEnabled || !hasRichFormatting
            ? normalTypingAttributes
            : (priorTyping[.font] == nil ? normalTypingAttributes : priorTyping)
        typingAttributes[.foregroundColor] = NSColor.black
        insertionPointColor = NSColor.black
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { previewTimer?.invalidate(); return }
        isPreview = true
        applyStyle()
        if let textContainer { layoutManager?.ensureLayout(for: textContainer) }
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !isPreview { schedulePreview() }
        needsDisplay = true
    }

    func insertChecklistItem() {
        window?.makeFirstResponder(self)
        let end = (string as NSString).length
        setSelectedRange(NSRange(location: end, length: 0))
        insertText((end == 0 || string.hasSuffix("\n") ? "" : "\n") + "- [ ] ", replacementRange: selectedRange())
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        typingAttributes = normalTypingAttributes
        scrollRangeToVisible(selectedRange())
    }

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let cursor = min(selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let lineText = ns.substring(with: line).trimmingCharacters(in: .newlines)
        if lineText.hasPrefix("• ") || lineText.hasPrefix("- ") && !lineText.hasPrefix("- [") {
            let prefix = String(lineText.prefix(2))
            if lineText.dropFirst(2).trimmingCharacters(in: .whitespaces).isEmpty {
                insertText("", replacementRange: NSRange(location: line.location, length: (lineText as NSString).length))
            } else { insertText("\n" + prefix, replacementRange: selectedRange()) }
            return
        }
        guard line.length >= 6 else { super.insertNewline(sender); return }
        let marker = NSRange(location: line.location, length: 6)
        let prefix = ns.substring(with: marker).lowercased()
        guard prefix == "- [ ] " || prefix == "- [x] " else { super.insertNewline(sender); return }
        let item = ns.substring(with: line).trimmingCharacters(in: .newlines)
        if item.count == 6 {
            insertText("", replacementRange: marker)
        } else {
            insertText("\n- [ ] ", replacementRange: selectedRange())
        }
    }

    var checklistIndent: CGFloat { ChecklistMarkGeometry.boxSize(font: noteFont) + 8 }

    private func taskFont(at character: Int) -> NSFont {
        guard let storage = textStorage else { return noteFont }
        let end = NSMaxRange((string as NSString).lineRange(for: NSRange(location: character, length: 0)))
        for index in (character + 6)..<max(character + 6, min(end, storage.length)) {
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont, font.pointSize >= 1 { return font }
        }
        return noteFont
    }

    func checkboxRect(at character: Int) -> NSRect? {
        guard !markdownEnabled || isPreview else { return nil }
        guard !codeRanges.contains(where: { NSLocationInRange(character, $0) }) else { return nil }
        guard let layoutManager, let textContainer, character < (string as NSString).length else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = lineRect.minY + layoutManager.location(forGlyphAt: glyph).y
        let font = taskFont(at: character)
        let size = ChecklistMarkGeometry.boxSize(font: font)
        return NSRect(x: textContainerOrigin.x + textContainer.lineFragmentPadding,
                      y: textContainerOrigin.y + baseline - ChecklistMarkGeometry.baselineOffset(font: font) - size / 2, width: size, height: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !markdownEnabled || isPreview else { return }
        let ns = string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard range.length >= 6 else { return }
            let prefix = ns.substring(with: NSRange(location: range.location, length: 6)).lowercased()
            guard prefix == "- [ ] " || prefix == "- [x] " else { return }
            guard let rect = self.checkboxRect(at: range.location) else { return }
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.width / 4, yRadius: rect.height / 4)
            NSColor.black.withAlphaComponent(0.42).setStroke(); path.lineWidth = 1.5; path.stroke()
            if prefix == "- [x] " {
                NSColor.black.withAlphaComponent(0.52).setFill(); path.fill()
                let points = ChecklistMarkGeometry.points(in: rect)
                let mark = NSBezierPath(); mark.move(to: points.start); mark.line(to: points.middle); mark.line(to: points.end)
                NSColor.white.setStroke(); mark.lineWidth = 1.8; mark.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager, let textContainer, !string.isEmpty {
            var local = point; local.x -= textContainerOrigin.x; local.y -= textContainerOrigin.y
            let glyph = min(layoutManager.glyphIndex(for: local, in: textContainer), max(0, layoutManager.numberOfGlyphs - 1))
            let character = layoutManager.characterIndexForGlyph(at: glyph)
            let line = (string as NSString).lineRange(for: NSRange(location: min(character, (string as NSString).length - 1), length: 0))
            if line.length >= 6 {
                let prefix = (string as NSString).substring(with: NSRange(location: line.location, length: 6)).lowercased()
                if (prefix == "- [ ] " || prefix == "- [x] "),
                   let checkbox = checkboxRect(at: line.location), checkbox.insetBy(dx: -3, dy: -3).contains(point) {
                    let lineText = (string as NSString).substring(with: line)
                    let contentRange = NSRange(location: line.location, length: line.length - (lineText.hasSuffix("\n") ? 1 : 0))
                    if !markdownEnabled, !lineText.contains("~~") {
                        let selection = selectedRange()
                        insertText(prefix == "- [x] " ? " " : "x", replacementRange: NSRange(location: line.location + 3, length: 1))
                        setSelectedRange(selection)
                        return
                    }
                    if let replacement = ChecklistLine.toggled((string as NSString).substring(with: contentRange)) {
                        insertText(replacement, replacementRange: contentRange)
                        return
                    }
                }
            }
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).insetBy(dx: -2, dy: -2)
            if glyphRect.contains(local), let url = textStorage?.attribute(.link, at: character, effectiveRange: nil) as? URL {
                let keyHeld = (0..<128).contains { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
                if Self.opensLink(with: event.modifierFlags, keyHeld: keyHeld) { NSWorkspace.shared.open(url) }
                else {
                    window?.makeFirstResponder(self)
                    setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
                }
                return
            }
        }
        if markdownEnabled && isPreview {
            let cursor = characterIndexForInsertion(at: point)
            beginSourceEditing()
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: min(cursor, (string as NSString).length), length: 0))
            return
        }
        beginSourceEditing()
        super.mouseDown(with: event)
        schedulePreview()
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard !markdownEnabled || !isPreview else { return }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    func richData() -> Data? {
        guard let storage = textStorage else { return nil }
        let clean = NSMutableAttributedString(attributedString: storage)
        // Display-only checklist markers must never become tiny text in the saved rich document.
        clean.enumerateAttribute(.font, in: NSRange(location: 0, length: clean.length)) { value, range, _ in
            if (value as? NSFont)?.pointSize ?? 0 < 1 { clean.addAttributes(self.normalTypingAttributes, range: range) }
        }
        return try? clean.data(from: NSRange(location: 0, length: clean.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    func loadRichText(_ data: Data?, baseSize: CGFloat? = nil) {
        guard !markdownEnabled else { return }
        hasRichFormatting = false
        textStorage?.setAttributes(normalTypingAttributes, range: NSRange(location: 0, length: (string as NSString).length))
        guard let rich = NoteMarkdown.normalizedRichText(data, matching: string, font: noteFont, baseSize: baseSize) else { return }
        hasRichFormatting = true
        textStorage?.setAttributedString(rich)
        typingAttributes = normalTypingAttributes
    }

    private func restoreFormatting(_ text: NSAttributedString, selection: NSRange) {
        guard let storage = textStorage else { return }
        let previous = NSAttributedString(attributedString: storage)
        let previousSelection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { $0.restoreFormatting(previous, selection: previousSelection) }
        storage.setAttributedString(text)
        setSelectedRange(selection)
        didChangeText()
    }

    @objc func boldSelection(_ sender: Any?) { format(trait: .boldFontMask) }
    @objc func italicSelection(_ sender: Any?) { format(trait: .italicFontMask) }

    func format(trait: NSFontTraitMask? = nil, heading: Int? = nil) {
        window?.makeFirstResponder(self)
        if markdownEnabled {
            beginSourceEditing()
            let range = selectedRange()
            let text = string as NSString
            if let heading {
                let lines = text.lineRange(for: range)
                let source = text.substring(with: lines)
                let replacement = source.components(separatedBy: "\n").enumerated().map { index, line in
                    if line.isEmpty && index > 0 { return line }
                    let body = line.replacingOccurrences(of: #"^#{1,6} "#, with: "", options: .regularExpression)
                    return String(repeating: "#", count: heading) + (heading == 0 ? "" : " ") + body
                }.joined(separator: "\n")
                insertText(replacement, replacementRange: lines)
            } else {
                let marker = trait == .boldFontMask ? "**" : "*"
                let selected = text.substring(with: range)
                if range.location >= marker.count, NSMaxRange(range) + marker.count <= text.length,
                   text.substring(with: NSRange(location: range.location - marker.count, length: marker.count)) == marker,
                   text.substring(with: NSRange(location: NSMaxRange(range), length: marker.count)) == marker {
                    insertText(selected, replacementRange: NSRange(location: range.location - marker.count, length: range.length + marker.count * 2))
                    setSelectedRange(NSRange(location: range.location - marker.count, length: range.length))
                } else {
                    insertText(marker + selected + marker, replacementRange: range)
                    setSelectedRange(NSRange(location: range.location + marker.count, length: range.length))
                }
            }
            return
        }
        guard let storage = textStorage else { return }
        hasRichFormatting = true
        let range = selectedRange()
        let manager = NSFontManager.shared
        let current = (range.length > 0 ? storage.attribute(.font, at: range.location, effectiveRange: nil) : typingAttributes[.font]) as? NSFont ?? noteFont
        var fonts = [NSFont]()
        if range.length > 0 {
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                let font = value as? NSFont ?? self.noteFont
                if font.pointSize >= 1 { fonts.append(font) }
            }
        } else { fonts = [current] }
        let remove = trait.map { trait in !fonts.isEmpty && fonts.allSatisfy { manager.traits(of: $0).contains(trait) } } ?? false
        func converted(_ font: NSFont) -> NSFont {
            if let heading {
                return heading == 0 ? noteFont : .systemFont(ofSize: noteFont.pointSize * [1, 1.65, 1.4, 1.2][heading], weight: .semibold)
            }
            return remove ? manager.convert(font, toNotHaveTrait: trait!) : NoteMarkdown.adding(trait!, to: font)
        }
        if range.length == 0 { typingAttributes[.font] = converted(current); return }
        let formatted = NSMutableAttributedString(attributedString: storage)
        formatted.enumerateAttribute(.font, in: range) { value, run, _ in
            formatted.addAttribute(.font, value: converted(value as? NSFont ?? self.noteFont), range: run)
        }
        restoreFormatting(formatted, selection: range)
        undoManager?.setActionName("Format Text")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": boldSelection(nil); return true
            case "i": italicSelection(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { cancelled?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelled?(); return }
        beginSourceEditing()
        super.keyDown(with: event)
    }
}

struct ChecklistMarkGeometry {
    static func baselineOffset(font: NSFont) -> CGFloat { font.capHeight / 2 }
    static func boxSize(font: NSFont) -> CGFloat { max(10, min(18, (font.pointSize * 0.75).rounded())) }

    static func points(in rect: NSRect) -> (start: NSPoint, middle: NSPoint, end: NSPoint) {
        (
            NSPoint(x: rect.minX + rect.width * 0.22, y: rect.midY),
            NSPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.75),
            NSPoint(x: rect.minX + rect.width * 0.81, y: rect.minY + rect.height * 0.25)
        )
    }
}

final class ChecklistEditorHandle: ObservableObject {
    weak var view: ChecklistNSTextView?
    func insertItem() { view?.insertChecklistItem() }
}

struct ChecklistTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richText: Data?
    let font: NSFont
    var richTextBaseSize: CGFloat? = nil
    var markdownEnabled = false
    var previewDelay: Double = 5
    let cancel: () -> Void
    let handle: ChecklistEditorHandle

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.focusRingType = .none; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true; scroll.verticalScroller?.controlSize = .mini; scroll.scrollerKnobStyle = .dark; scroll.verticalScroller?.appearance = NSAppearance(named: .aqua)
        let view = ChecklistNSTextView(); view.drawsBackground = false; view.isRichText = !markdownEnabled; view.importsGraphics = false; view.allowsUndo = true; view.usesFindPanel = true; view.isIncrementalSearchingEnabled = true; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isContinuousSpellCheckingEnabled = true; view.isGrammarCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.focusRingType = .none; view.textContainerInset = NSSize(width: 0, height: 8); view.textContainer?.widthTracksTextView = true; view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.noteFont = font; view.markdownEnabled = markdownEnabled; view.previewDelay = previewDelay; view.string = text; view.loadRichText(richText, baseSize: richTextBaseSize); view.applyStyle(); view.cancelled = cancel; view.changed = { value in if value != text { text = value } }
        view.richChanged = { richText = $0 }
        handle.view = view
        scroll.documentView = view
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? ChecklistNSTextView else { return }
        handle.view = view
        let fontChanged = view.noteFont.fontName != font.fontName || view.noteFont.pointSize != font.pointSize
        let textChanged = view.string != text
        let markdownChanged = view.markdownEnabled != markdownEnabled
        view.noteFont = font; view.markdownEnabled = markdownEnabled; view.isRichText = !markdownEnabled; view.previewDelay = previewDelay; view.cancelled = cancel
        if textChanged { view.string = text }
        if textChanged || markdownChanged { view.loadRichText(richText, baseSize: richTextBaseSize) }
        if markdownChanged && markdownEnabled { view.showPreview() }
        if textChanged || fontChanged || markdownChanged { view.applyStyle(); view.needsDisplay = true }
    }
}

private struct NoteIconPicker: View {
    @Binding var selection: String
    let options: [String]
    let label: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: selection).font(.system(size: 14))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.frame(height: 26).padding(.horizontal, 4).contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle()).accessibilityLabel(label)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: options.count > 6 ? 4 : 3), spacing: 6) {
                ForEach(options, id: \.self) { symbol in
                    Button { selection = symbol; showing = false } label: {
                        Image(systemName: symbol).font(.system(size: 16))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(selection == symbol ? appAccentForeground : Color.primary)
                            .background(selection == symbol ? appAccent : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverButtonStyle())
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityValue(selection == symbol ? "Selected" : "Not selected")
                }
            }.frame(width: options.count > 6 ? 154 : 114).padding(10)
        }
    }
}

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let noteID: UUID
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    let close: () -> Void
    let archive: () -> Void
    let delete: () -> Void
    let pin: (Bool) -> Void
    @State private var note: Note
    @State private var closeHovered = false
    @StateObject private var checklistEditor = ChecklistEditorHandle()

    init(noteID: UUID, store: NotesStore, settings: AppSettings, close: @escaping () -> Void, archive: @escaping () -> Void, delete: @escaping () -> Void, pin: @escaping (Bool) -> Void) {
        self.noteID = noteID; self.store = store; self.settings = settings; self.close = close; self.archive = archive; self.delete = delete; self.pin = pin
        _note = State(initialValue: store.note(noteID) ?? Note(id: noteID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button(action: close) {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle().fill(closeHovered ? Color(nsColor: .systemRed) : .black.opacity(0.30))
                        }.frame(width: 12, height: 12)
                        Circle().fill(.black.opacity(0.12)).frame(width: 12, height: 12)
                    }.frame(width: 34, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain).onHover { closeHovered = $0 }.animation(.easeOut(duration: 0.10), value: closeHovered)
                .accessibilityLabel("Close note").help("Close this note and return to the deck")
                NoteIconPicker(selection: Binding(get: { note.symbol }, set: { setIcon($0) }), options: NoteIcons.all, label: "Choose note icon")
                TextField("Untitled note", text: $note.title).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Saved · \(shortAge(note.updatedAt))").font(.system(size: 11)).foregroundStyle(.black.opacity(0.42))
                if settings.shareNotes {
                    ShareLink(item: NoteFile(note: note), preview: SharePreview(note.title)) {
                        Image(systemName: "square.and.arrow.up").resizable().scaledToFit()
                            .frame(width: 14, height: 14).frame(width: 24, height: 24)
                    }.buttonStyle(HoverButtonStyle()).foregroundStyle(.black.opacity(0.48)).tint(.black.opacity(0.48)).help("Share as Markdown").accessibilityLabel("Share as Markdown")
                }
                DragHandle().frame(width: 24, height: 24).help("Drag to move; drag an edge or corner to resize")
                Button { note.pinned.toggle(); save(immediate: true); pin(note.pinned) } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin").resizable().scaledToFit()
                        .frame(width: 14, height: 14).frame(width: 24, height: 24)
                        .background(note.pinned ? .black.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(HoverButtonStyle()).foregroundStyle(.black.opacity(0.48)).help(note.pinned ? "Unpin from desktop" : "Pin note to desktop")
            }
            .padding(.horizontal, 16).frame(height: 47)
            Divider().opacity(0.22).padding(.horizontal, 16)
            ChecklistTextEditor(text: $note.body, richText: Binding(get: { note.presentation?.richText }, set: { data in
                if note.presentation == nil { note.presentation = NotePresentation() }
                note.presentation?.richText = data
                note.presentation?.richTextBaseSize = settings.textSize
                save()
            }), font: settings.nsNoteFont, richTextBaseSize: note.presentation?.richTextBaseSize.map { CGFloat($0) }, markdownEnabled: settings.markdownEnabled, previewDelay: settings.markdownPreviewDelay, cancel: close, handle: checklistEditor).padding(.horizontal, 17)
            Divider().opacity(0.2)
            HStack(spacing: 8) {
                Menu {
                    ForEach(NoteColor.allCases, id: \.rawValue) { value in
                        Button(value.name) { note.color = value; note.presentation?.colorHex = nil; save(immediate: true) }
                    }
                } label: { Image(systemName: "paintpalette").frame(width: 22, height: 24) }
                .menuStyle(.borderlessButton).fixedSize().help("Note color presets")
                Menu {
                    Button("Bold    ⌘B") { checklistEditor.view?.boldSelection(nil) }
                    Button("Italic    ⌘I") { checklistEditor.view?.italicSelection(nil) }
                    Divider()
                    Button("Body") { checklistEditor.view?.format(heading: 0) }
                    ForEach(1...3, id: \.self) { level in
                        Button("Heading \(level)") { checklistEditor.view?.format(heading: level) }
                    }
                } label: { Image(systemName: "textformat.size").frame(width: 22, height: 24) }
                .menuStyle(.borderlessButton).fixedSize().help("Format selected text").accessibilityLabel("Text formatting")
                Button(action: checklistEditor.insertItem) {
                    Image(systemName: "checklist").frame(width: 25, height: 25)
                }
                .buttonStyle(HoverButtonStyle()).accessibilityLabel("Add checklist item").help("Add a checklist item")
                Spacer()
                Button("Delete", role: .destructive, action: delete).buttonStyle(MatteButtonStyle(fill: .red.opacity(0.13), foreground: Color(red: 0.62, green: 0.08, blue: 0.06), width: 58)).fixedSize()
                Button("Mark complete", action: archive).buttonStyle(MatteButtonStyle(fill: .black.opacity(0.15), foreground: .black.opacity(0.78), width: 100)).fixedSize()
                Button("Close", action: close).buttonStyle(MatteButtonStyle(fill: .black.opacity(0.10), foreground: .black.opacity(0.78), width: 53)).fixedSize()
            }
            .padding(.horizontal, 16).frame(height: 51)
            .environment(\.colorScheme, .light)
            .background {
                Group {
                    Button("") { cycleColor() }.keyboardShortcut(".", modifiers: .command)
                    Button("") { delete() }.keyboardShortcut(.delete, modifiers: .command)
                }.frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            }
        }
        .foregroundStyle(.black.opacity(0.73))
        .background(note.displayColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: note.title) { _ in save() }
        .onChange(of: note.body) { _ in save() }
        .onChange(of: store.notes) { _ in if let fresh = store.note(noteID), fresh.updatedAt > note.updatedAt { note = fresh } }
        .onExitCommand(perform: close)
    }

    private func setIcon(_ symbol: String) {
        if note.presentation == nil { note.presentation = NotePresentation() }
        note.presentation?.icon = symbol
        save(immediate: true)
    }

    private func cycleColor() {
        note.presentation?.colorHex = nil
        note.color = note.color.next
        save(immediate: true)
    }

    private func save(immediate: Bool = false) {
        note.updatedAt = Date()
        store.update(note, immediate: immediate)
    }
}

enum NoteFilter: String, CaseIterable { case all = "All", active = "Active", archived = "Archived" }

struct AllNotesView: View {
    @ObservedObject var store: NotesStore
    @State private var filter: NoteFilter
    @State private var query = ""
    @State private var selected: Set<UUID> = []
    @State private var focused: UUID?
    @State private var exportFormat = ExportFormat.markdown
    let open: (UUID) -> Void

    init(store: NotesStore, initialFilter: NoteFilter, open: @escaping (UUID) -> Void) {
        self.store = store; _filter = State(initialValue: initialFilter); self.open = open
    }

    private var filtered: [Note] {
        store.search(query).filter {
            switch filter { case .all: true; case .active: $0.archivedAt == nil; case .archived: $0.archivedAt != nil }
        }
    }
    private var current: Note? { selected.count == 1 ? selected.first.flatMap(store.note) : focused.flatMap(store.note) ?? filtered.first }
    private var actionNotes: [Note] {
        let ids = selected.isEmpty ? Set(current.map { [$0.id] } ?? []) : selected
        return filtered.filter { ids.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("All Notes").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { ExportController.importNotes(into: store) } label: { Label("Import…", systemImage: "square.and.arrow.down").lineLimit(1) }
                        .buttonStyle(MatteButtonStyle(width: 76)).fixedSize()
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search all notes", text: $query).textFieldStyle(.plain)
                    Text("\(filtered.count) \(filtered.count == 1 ? "note" : "notes")").foregroundStyle(.secondary).font(.caption2)
                }
                .padding(.horizontal, 10).frame(height: 31).background(appSearch, in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 7) { ForEach(NoteFilter.allCases, id: \.self) { filterButton($0) } }
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filtered) { note in
                            Button { focused = note.id } label: { noteRow(note) }
                                .buttonStyle(.plain)
                                .onTapGesture(count: 2) { open(note.id) }
                                .accessibilityAction(named: "Open") { open(note.id) }
                        }
                    }
                }
                .padding(6)
                .modifier(SurfaceCard())
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12).frame(width: 390).background(appSidebar)
            Divider()
            Group {
                if selected.count > 1 {
                    selectionPane
                } else if let note = current {
                    previewPane(note)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "note.text").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("Nothing here yet").font(.headline)
                        Text("Create a note from the edge of the screen.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 17).padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(appPaper)
        .onChange(of: filter) { _ in focused = nil; selected.removeAll() }
        .alert("Margin", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .safeAreaInset(edge: .bottom) {
            if let undo = store.undoNote { HStack { Text("\(undo.title) deleted"); Button("Undo") { store.undoDelete() } }.padding(9).background(.regularMaterial, in: Capsule()).padding(8) }
        }
    }

    private func filterButton(_ value: NoteFilter) -> some View {
        let isSelected = filter == value
        return Button { filter = value; focused = nil; selected.removeAll() } label: {
            HStack(spacing: 5) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(value.rawValue)
            }
        }
            .buttonStyle(HoverButtonStyle()).font(.system(size: 12, weight: filter == value ? .semibold : .regular))
            .foregroundStyle(isSelected ? appAccentForeground : .secondary)
            .padding(.horizontal, 11).frame(height: 27)
            .background(isSelected ? appAccent : .clear, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Button { if selected.contains(note.id) { selected.remove(note.id) } else { selected.insert(note.id); focused = note.id } } label: {
                RoundedRectangle(cornerRadius: 5).fill(selected.contains(note.id) ? appAccent : .clear).frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(selected.contains(note.id) ? 0 : 0.22), lineWidth: 1.5))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(appAccentForeground).opacity(selected.contains(note.id) ? 1 : 0))
            }.buttonStyle(HoverButtonStyle()).accessibilityLabel(selected.contains(note.id) ? "Deselect \(note.title)" : "Select \(note.title)")
            Capsule().fill(note.displayColor).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Label(note.title, systemImage: note.symbol).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text(note.archivedAt == nil ? "ACTIVE" : "ARCHIVED").font(.system(size: 9, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5)); Text(shortAge(note.updatedAt)).font(.caption2).foregroundStyle(.secondary) }
                ChecklistPreviewLine(line: note.body.components(separatedBy: "\n").first ?? "", font: store.settings.nsListFont)
                    .font(store.settings.listFont).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 7).contentShape(Rectangle())
        .background((focused == note.id || selected.contains(note.id)) ? appSelectionSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((focused == note.id || selected.contains(note.id)) ? appSelectionBorder : .clear, lineWidth: 1))
    }

    private func previewPane(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundedRectangle(cornerRadius: 3).fill(note.displayColor).frame(width: 9, height: 9)
                Text(note.archivedAt == nil ? "ACTIVE · IN\nTHE DECK" : "ARCHIVED · \(shortAge(note.archivedAt!).uppercased())")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                Spacer()
                Button(note.archivedAt == nil ? "Mark complete" : "Restore to deck") { note.archivedAt == nil ? store.archive(note.id) : store.restore(note.id) }.buttonStyle(MatteButtonStyle())
                Button("Export…") { ExportController.export(.markdown, notes: [note], store: store) }.buttonStyle(MatteButtonStyle())
                Button("Delete", role: .destructive) { store.delete(note.id) }.buttonStyle(MatteButtonStyle(fill: .red.opacity(0.10), foreground: .red.opacity(0.72)))
            }
            Button { open(note.id) } label: { NotePreview(note: note, settings: store.settings) }
                .buttonStyle(.plain).help("Open note")
            Spacer(minLength: 0)
        }
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("\(selected.count) notes selected").font(.system(size: 13, weight: .semibold))
                Spacer(); Button("Clear") { selected.removeAll() }.buttonStyle(HoverButtonStyle()).font(.caption).foregroundStyle(.secondary)
            }
            selectionStack.frame(height: 96)
            Text("EXPORT AS").font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
            VStack(spacing: 5) { ForEach(ExportFormat.allCases, id: \.self) { exportOption($0) } }
            Spacer()
            HStack {
                Button("Export \(selected.count) notes") { ExportController.export(exportFormat, notes: actionNotes, store: store) }
                    .buttonStyle(MatteButtonStyle(fill: appAccent, foreground: appAccentForeground))
                Spacer()
                Button(actionNotes.allSatisfy { $0.archivedAt != nil } ? "Restore" : "Archive") {
                    let restoring = actionNotes.allSatisfy { $0.archivedAt != nil }
                    actionNotes.forEach { restoring ? store.restore($0.id) : store.archive($0.id) }; selected.removeAll()
                }.buttonStyle(MatteButtonStyle())
                Button("Delete", role: .destructive) { actionNotes.forEach { store.delete($0.id) }; selected.removeAll() }
                    .buttonStyle(MatteButtonStyle(fill: .red.opacity(0.10), foreground: .red.opacity(0.72)))
            }
        }
    }

    private var selectionStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(actionNotes.prefix(3).enumerated()).reversed(), id: \.element.id) { index, note in
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                    Text(note.body).font(.system(size: 9)).lineLimit(2).foregroundStyle(.black.opacity(0.62))
                }
                .padding(10).frame(width: 150, height: 80, alignment: .topLeading)
                .background(note.displayColor, in: RoundedRectangle(cornerRadius: 11)).modifier(CardShadow())
                .offset(x: CGFloat(index) * 18, y: CGFloat(index) * 5)
            }
        }
    }

    private func exportOption(_ format: ExportFormat) -> some View {
        let isSelected = exportFormat == format
        return Button { exportFormat = format } label: {
            HStack(spacing: 9) {
                Circle().stroke(isSelected ? appAccent : Color.primary.opacity(0.32), lineWidth: 1.5).frame(width: 15, height: 15)
                    .overlay(Circle().fill(appAccent).frame(width: 7, height: 7).opacity(isSelected ? 1 : 0))
                Text(format.title).font(.system(size: 12, weight: .semibold)); Text("— \(format.detail)").font(.caption).foregroundStyle(.secondary); Spacer()
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(isSelected ? appSelectionSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? appSelectionBorder : .clear, lineWidth: 1))
        }.buttonStyle(HoverButtonStyle()).accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct NotePreview: View {
    let note: Note
    @ObservedObject var settings: AppSettings
    var height: CGFloat = 336
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label(note.title, systemImage: note.symbol).font(.system(size: 17, weight: .bold)); Spacer(); Text("edited \(note.updatedAt.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.black.opacity(0.46)) }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text(NoteMarkdown.preview(note, font: settings.nsNoteFont, markdown: settings.markdownEnabled))
                }
                .font(settings.noteFont).foregroundStyle(.black.opacity(0.72)).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider().opacity(0.25)
            Text(metadata).font(.caption).foregroundStyle(.black.opacity(0.46))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .foregroundStyle(.black.opacity(0.76))
        .background(note.displayColor, in: RoundedRectangle(cornerRadius: 18)).modifier(CardShadow(lifted: true))
    }

    private var metadata: String {
        var value = "Created \(note.createdAt.formatted(.dateTime.day().month(.abbreviated).year())) · Updated \(agePhrase(note.updatedAt))"
        if let archivedAt = note.archivedAt { value += " · Archived \(agePhrase(archivedAt))" }
        return value
    }
}

struct ChecklistLine {
    static func parse(_ line: String) -> (checked: Bool, text: String)? {
        let marker = line.prefix(6).lowercased()
        guard marker == "- [ ] " || marker == "- [x] " else { return nil }
        let checked = marker == "- [x] "
        var text = String(line.dropFirst(6))
        if checked, text.hasPrefix("~~"), text.hasSuffix("~~"), text.count >= 4 {
            text = String(text.dropFirst(2).dropLast(2))
        }
        return (checked, text)
    }

    static func toggled(_ line: String) -> String? {
        guard let item = parse(line) else { return nil }
        return item.checked ? "- [ ] \(item.text)" : "- [x] ~~\(item.text)~~"
    }
}

struct ArchiveView: View {
    @ObservedObject var store: NotesStore
    @State private var query = ""
    @State private var focused: UUID?
    let open: (UUID) -> Void

    private var filtered: [Note] { store.search(query, archivedOnly: true) }
    private var current: Note? { focused.flatMap(store.note) ?? filtered.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Archive").font(.system(size: 15, weight: .bold))
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search archived notes", text: $query).textFieldStyle(.plain)
                    Text("\(filtered.count) \(filtered.count == 1 ? "note" : "notes")").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).frame(height: 31).background(appSearch, in: RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filtered) { note in
                            Button { focused = note.id } label: { archiveRow(note) }
                                .buttonStyle(.plain)
                                .onTapGesture(count: 2) { open(note.id) }
                                .accessibilityAction(named: "Open") { open(note.id) }
                        }
                    }
                }
                .padding(6)
                .modifier(SurfaceCard())
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12).frame(width: 351).background(appSidebar)
            Divider()
            Group {
                if let note = current {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(note.displayColor).frame(width: 9, height: 9)
                            Text(archiveStatus(note)).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore to deck") { store.restore(note.id) }.buttonStyle(MatteButtonStyle())
                            Button("Delete", role: .destructive) { store.delete(note.id) }.buttonStyle(MatteButtonStyle(fill: .red.opacity(0.10), foreground: .red.opacity(0.72)))
                        }
                        NotePreview(note: note, settings: store.settings, height: 360)
                    }
                } else { VStack { Image(systemName: "archivebox").font(.system(size: 30)); Text("Nothing archived yet.") }.foregroundStyle(.secondary) }
            }.padding(.leading, 24).padding(.trailing, 14).padding(.top, 21).padding(.bottom, 14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(appPaper)
        .alert("Margin", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .safeAreaInset(edge: .bottom) {
            if let undo = store.undoNote { HStack { Text("\(undo.title) deleted"); Button("Undo") { store.undoDelete() } }.padding(9).background(.regularMaterial, in: Capsule()).padding(8) }
        }
    }

    private func archiveRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(note.displayColor).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Label(note.title, systemImage: note.symbol).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text(shortAge(note.archivedAt ?? note.updatedAt)).font(.caption2).foregroundStyle(.secondary) }
                ChecklistPreviewLine(line: note.body.components(separatedBy: "\n").first ?? "", font: store.settings.nsListFont)
                    .font(store.settings.listFont).lineLimit(1).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 7).padding(.horizontal, 7).contentShape(Rectangle())
            .background(focused == note.id ? appSelectionSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused == note.id ? appSelectionBorder : .clear, lineWidth: 1))
    }

    private func archiveStatus(_ note: Note) -> String {
        let age = shortAge(note.archivedAt ?? note.updatedAt)
        return age == "now" ? "ARCHIVED JUST NOW" : "ARCHIVED \(age.uppercased()) AGO"
    }
}

enum ExportFormat: CaseIterable, Hashable {
    case markdown, text, single, stickies
    var title: String { switch self { case .markdown: "Markdown"; case .text: "Plain text"; case .single: "Single file"; case .stickies: "Sticky archive" } }
    var detail: String { switch self { case .markdown: "one .md file per note"; case .text: "one .txt file per note"; case .single: "all notes in one document"; case .stickies: ".stickies — colors and dates kept" } }
}
enum ExportController {
    static func importNotes(into store: NotesStore) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "stickies")!, .plainText, UTType(filenameExtension: "md")!]
        guard panel.runModal() == .OK else { return }
        store.importFiles(panel.urls)
    }

    static func export(_ format: ExportFormat, notes: [Note], store: NotesStore) {
        guard !notes.isEmpty else { return }
        do {
            switch format {
            case .markdown, .text:
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Export Here"
                guard panel.runModal() == .OK, let folder = panel.url else { return }
                let ext = format == .markdown ? "md" : "txt"
                for note in notes { try note.body.write(to: folder.appendingPathComponent(safe(note.title)).appendingPathExtension(ext), atomically: true, encoding: .utf8) }
            case .single:
                let panel = NSSavePanel(); panel.nameFieldStringValue = "Margin.md"; panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let text = notes.map { "# \($0.title)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
                try text.write(to: url, atomically: true, encoding: .utf8)
            case .stickies:
                let panel = NSSavePanel(); panel.nameFieldStringValue = "Margin.stickies"; panel.allowedContentTypes = [UTType(filenameExtension: "stickies")!]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try store.archiveData(notes).write(to: url, options: .atomic)
            }
        } catch { store.errorMessage = error.localizedDescription }
    }

    private static func safe(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\0").union(.newlines)
        let name = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled note" : name
    }
}

private enum SettingsTab: String, CaseIterable { case general = "General", notes = "Notes", appearance = "Appearance", calendar = "Calendar", shortcuts = "Keyboard", system = "System", cloud = "Cloud Sync", about = "About" }

enum SettingsPalette {
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { color($0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light) })
    }
    static let surface = adaptive(0xF3F1EC, 0x23231F)
    static let shell = adaptive(0xE5E2DA, 0x34342F)
    static let well = adaptive(0xE8E5DD, 0x191A17)
    static let ink = adaptive(0x292824, 0xF1EEE5)
    static let secondary = adaptive(0x65625B, 0xB8B4A9)
    static func font(_ size: CGFloat, medium: Bool = false) -> Font { .custom(medium ? "Satoshi-Medium" : "Satoshi-Regular", size: size) }
}

extension InterfaceColor {
    func nsColor(isDark: Bool) -> NSColor {
        let pair: (UInt32, UInt32) = switch self {
        case .clay: (0x995039, 0xE1A48B)
        case .olive: (0x536245, 0xB2C29D)
        case .slate: (0x4C657B, 0xA5C1D8)
        case .plum: (0x755675, 0xD2ACD3)
        case .graphite: (0x65615A, 0xCEC7BA)
        }
        return SettingsPalette.color(isDark ? pair.1 : pair.0)
    }
}

extension Notification.Name {
    static let marginShortcutRecording = Notification.Name("MarginShortcutRecording")
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut = GlobalShortcut.standard { didSet { if !recording { title = shortcut.display } } }
    var changed: ((GlobalShortcut) -> Bool)?
    private var recording = false {
        didSet {
            if recording != oldValue { NotificationCenter.default.post(name: .marginShortcutRecording, object: recording) }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isBordered = false; font = NSFont(name: "Satoshi-Medium", size: 12)
        target = self; action = #selector(beginRecording); title = shortcut.display
        toolTip = "Click, then press a shortcut"
    }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        recording = true; title = "Press shortcut…"
    }

    override func resignFirstResponder() -> Bool {
        cancelOperation(nil)
        return super.resignFirstResponder()
    }
    override func cancelOperation(_ sender: Any?) { recording = false; title = shortcut.display }
    override func keyDown(with event: NSEvent) { if recording { record(event) } else { super.keyDown(with: event) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        record(event); return true
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { cancelOperation(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0,
              let key = Self.keyName(event) else { NSSound.beep(); return }
        let candidate = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        guard changed?(candidate) != false else { NSSound.beep(); return }
        shortcut = candidate
        recording = false; title = shortcut.display
    }

    private static func keyName(_ event: NSEvent) -> String? {
        let code = Int(event.keyCode)
        switch code {
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let functions = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            return functions.firstIndex(of: code).map { "F\($0 + 1)" }
                ?? event.charactersIgnoringModifiers?.uppercased().first.map(String.init)
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let changed: (GlobalShortcut) -> Bool

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let view = ShortcutRecorderButton()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: ShortcutRecorderButton, context: Context) { view.shortcut = shortcut; view.changed = changed }
}

private struct AccentSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    let accessibilityLabel: String
    var accent: NSColor = MarginPalette.accent

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    Text(option.label).font(SettingsPalette.font(12, medium: selection == option.value))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(selection == option.value ? Color(nsColor: accent) : SettingsPalette.secondary)
                        .background(selection == option.value ? SettingsPalette.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(accessibilityLabel): \(option.label)")
                    .accessibilityValue(selection == option.value ? "Selected" : "Not selected")
            }
        }
        .padding(3).background(SettingsPalette.well, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SettingsMenu<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    func makeNSView(context: Context) -> NSPopUpButton {
        let control = NSPopUpButton(frame: .zero, pullsDown: false)
        control.isBordered = false; control.alignment = .left
        (control.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        control.font = NSFont(name: "Satoshi-Regular", size: 12)
        control.target = context.coordinator; control.action = #selector(Coordinator.changed(_:))
        control.setAccessibilityLabel(title)
        return control
    }

    func updateNSView(_ control: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection; context.coordinator.values = options.map(\.0)
        if control.itemTitles != options.map(\.1) { control.removeAllItems(); control.addItems(withTitles: options.map(\.1)) }
        control.selectItem(at: options.firstIndex { $0.0 == selection } ?? -1)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value] = []
        init(selection: Binding<Value>) { self.selection = selection }
        @objc func changed(_ control: NSPopUpButton) {
            guard values.indices.contains(control.indexOfSelectedItem) else { return }
            selection.wrappedValue = values[control.indexOfSelectedItem]
        }
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SettingsPalette.font(12, medium: true)).padding(.horizontal, 12).frame(height: 30)
            .background(SettingsPalette.well, in: RoundedRectangle(cornerRadius: 8)).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct SettingsNoteBody: NSViewRepresentable {
    let text: String
    let font: NSFont
    let markdownEnabled: Bool

    func makeNSView(context: Context) -> ChecklistNSTextView {
        let view = ChecklistNSTextView()
        view.drawsBackground = false; view.isEditable = false; view.isSelectable = false
        view.textContainerInset = NSSize(width: 0, height: 8)
        view.textContainer?.lineFragmentPadding = 5
        view.textContainer?.widthTracksTextView = true
        return view
    }

    func updateNSView(_ view: ChecklistNSTextView, context: Context) {
        view.string = text; view.noteFont = font; view.markdownEnabled = markdownEnabled
        view.applyStyle(); view.needsDisplay = true
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: NotesStore
    @ObservedObject var cloudSync: CloudSyncController
    let updater: SPUUpdater
    @State private var tab = SettingsTab.appearance
    @State private var previewIndex = 0
    @State private var screens = NSScreen.screens
    @StateObject private var calendarAgenda = CalendarAgenda()

    static func visibleVersion(shortVersion: String) -> String { shortVersion }

    private var surface: Color { SettingsPalette.surface }
    private var secondaryInk: Color { SettingsPalette.secondary }
    private var accent: Color { Color(nsColor: settings.interfaceColor.nsColor(isDark: colorScheme == .dark)) }
    private var rule: Color { SettingsPalette.ink.opacity(contrast == .increased ? 0.55 : 0.10) }
    private var displayOptions: [(String, String)] {
        var options = [("main", "Main display"), ("all", "All displays")] + screens.map { ($0.displayID, $0.localizedName) }
        if !options.contains(where: { $0.0 == settings.display }) { options.append((settings.display, "Disconnected display")) }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Color.clear.frame(width: 90, height: 1)
                Spacer()
                Text("margin").font(SettingsPalette.font(20, medium: true)).tracking(-0.7)
                Spacer()
                Text("Settings").font(SettingsPalette.font(11)).foregroundStyle(secondaryInk).frame(width: 90, alignment: .trailing)
            }.padding(.horizontal, 24).frame(height: 44)
            HStack(spacing: 24) {
                ForEach(SettingsTab.allCases, id: \.self) { value in tabButton(value) }
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 20)
            .overlay(alignment: .bottom) { rule.frame(height: 1) }.padding(.horizontal, 25)
            Group {
                VStack(spacing: 14) {
                    Group {
                        switch tab {
                        case .general: general
                        case .notes: notes
                        case .cloud: cloud
                        case .shortcuts: shortcuts
                        case .system: system
                        case .appearance: appearance
                        case .calendar: calendarSettings
                        case .about: about
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top).fixedSize(horizontal: false, vertical: true)

                }
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            HStack {
                Text("Margin \(versionText)")
                Spacer()
                Text("Changes save automatically.")
            }
            .font(SettingsPalette.font(10)).foregroundStyle(secondaryInk)
            .padding(.top, 10).overlay(alignment: .top) { rule.frame(height: 1) }
            .padding(.horizontal, 28).padding(.bottom, 12)
        }
        .font(SettingsPalette.font(13)).foregroundStyle(SettingsPalette.ink)
        .tint(accent).background(surface)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        .onChange(of: settings.calendarVisibleIDs) { value in calendarAgenda.calendarIDs = value; calendarAgenda.refresh() }
        .onChange(of: calendarAgenda.calendarIDs) { value in if settings.calendarVisibleIDs != value { settings.calendarVisibleIDs = value } }
    }

    private func tabButton(_ value: SettingsTab) -> some View {
        Button { tab = value } label: {
            Text(value.rawValue).font(SettingsPalette.font(12, medium: tab == value))
                .foregroundStyle(tab == value ? SettingsPalette.ink : secondaryInk)
                .padding(.top, 6).padding(.bottom, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(tab == value ? accent : .clear).frame(height: 2) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(value == .cloud).opacity(value == .cloud ? 0.4 : 1)
        .help(value == .cloud ? "Cloud Sync is coming later" : value.rawValue)
        .accessibilityValue(tab == value ? "Selected" : "Not selected")
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Deck") {
                settingRow("Screen side", "Which edge the deck lives on") { AccentSegmentedPicker(selection: $settings.side, options: [(.left, "Left"), (.right, "Right"), (.bottom, "Bottom")], accessibilityLabel: "Screen side", accent: settings.interfaceColor.nsColor(isDark: colorScheme == .dark)).frame(width: 200, height: 30) }
                settingRow("Open a note", "Choose how to open a card in the deck") { AccentSegmentedPicker(selection: $settings.fanMode, options: [(.hover, "On hover"), (.click, "On click")], accessibilityLabel: "Open a note", accent: settings.interfaceColor.nsColor(isDark: colorScheme == .dark)).frame(width: 200, height: 30) }
                settingRow("Keep the deck open", "Leave the cards visible at the screen edge") { Toggle("Keep the deck open", isOn: $settings.keepOpen).toggleStyle(.switch).labelsHidden().tint(accent) }
                settingRow("Activation delay", "Wait before opening the deck on hover") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.activationDelay, in: 0...1).frame(width: 140).accessibilityLabel("Activation delay")
                        Text("\(Int((settings.activationDelay * 1000).rounded())) ms").monospacedDigit().frame(width: 55, alignment: .trailing)
                    }
                }
                settingRow("Display", "Choose a display, or show the deck on all of them") {
                    settingsMenu("Display", selection: $settings.display, options: displayOptions, width: 200)
                }
                settingRow("Animation speed", "How briskly the deck moves", divider: false) { AccentSegmentedPicker(selection: $settings.animationSpeed, options: [(.fast, "Fast"), (.normal, "Normal"), (.slow, "Slow")], accessibilityLabel: "Animation speed", accent: settings.interfaceColor.nsColor(isDark: colorScheme == .dark)).frame(width: 200, height: 30) }
            }
        }
    }

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Calendar wing") {
                settingRow("Calendar wing", "Turn this off to remove the calendar completely") {
                    Toggle("Calendar wing", isOn: $settings.calendarEnabled).toggleStyle(.switch).labelsHidden().tint(accent)
                }
                settingRow("Wing position", "Choose an end, or drag the wing directly between notes") {
                    AccentSegmentedPicker(selection: $settings.calendarPosition,
                                          options: [(0, "Top"), (Int.max, "Bottom")],
                                          accessibilityLabel: "Calendar wing position",
                                          accent: settings.interfaceColor.nsColor(isDark: colorScheme == .dark))
                        .frame(width: 150, height: 30).disabled(!settings.calendarEnabled)
                }
                settingRow("Calendar color", "Used for the wing and calendar window", divider: false) {
                    HStack(spacing: 4) {
                        ForEach(NoteColor.allCases, id: \.rawValue) { value in
                            swatch(value.color, selected: settings.calendarColor == value, label: "\(value.name) calendar color") {
                                settings.calendarColor = value
                            }
                        }
                    }
                }
            }
            settingsSection("Calendar access") {
                if calendarAgenda.authorized {
                    settingRow("Calendars shown", "Choose one calendar or combine all connected accounts") {
                        Menu {
                            Button { settings.calendarVisibleIDs = [] } label: {
                                if settings.calendarVisibleIDs.isEmpty { Label("All calendars", systemImage: "checkmark") }
                                else { Text("All calendars") }
                            }
                            Divider()
                            ForEach(calendarAgenda.calendars, id: \.calendarIdentifier) { calendar in
                                Button { toggleCalendar(calendar.calendarIdentifier) } label: {
                                    let name = "\(calendar.title) · \(calendar.source.title)"
                                    if settings.calendarVisibleIDs.contains(calendar.calendarIdentifier) { Label(name, systemImage: "checkmark") }
                                    else { Text(name) }
                                }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Text(calendarSelectionLabel).lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            }
                        }.buttonStyle(SettingsButtonStyle()).frame(width: 220)
                    }
                    settingRow("Primary calendar", "New events save here unless you choose another calendar") {
                        settingsMenu("Primary calendar", selection: $settings.calendarID, options: primaryCalendarOptions, width: 220)
                    }
                    settingRow("Connection", "Managed securely by macOS Calendar", divider: false) {
                        Button("Open Calendar", action: CalendarAgenda.openCalendar).buttonStyle(SettingsButtonStyle())
                    }
                } else {
                    settingRow("Calendar access", calendarAgenda.message) {
                        Button(calendarAgenda.requesting ? "Waiting…" : "Allow Access") { calendarAgenda.requestAccess() }
                            .buttonStyle(SettingsButtonStyle()).disabled(calendarAgenda.requesting)
                    }
                    settingRow("Privacy controls", "Change access later in System Settings", divider: false) {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }.buttonStyle(SettingsButtonStyle())
                    }
                }
            }
        }
        .onAppear {
            calendarAgenda.calendarIDs = settings.calendarVisibleIDs; calendarAgenda.refresh()
            if !primaryCalendarOptions.contains(where: { $0.0 == settings.calendarID }) {
                settings.calendarID = primaryCalendarOptions.first?.0 ?? ""
            }
        }
    }

    private var calendarSelectionLabel: String {
        if settings.calendarVisibleIDs.isEmpty { return "All calendars" }
        if settings.calendarVisibleIDs.count == 1 {
            return calendarAgenda.calendars.first { $0.calendarIdentifier == settings.calendarVisibleIDs[0] }?.title ?? "1 calendar"
        }
        return "\(settings.calendarVisibleIDs.count) calendars"
    }

    private var primaryCalendarOptions: [(String, String)] {
        calendarAgenda.writableCalendars.map { ($0.calendarIdentifier, "\($0.title) · \($0.source.title)") }
    }

    private func toggleCalendar(_ id: String) {
        if settings.calendarVisibleIDs.isEmpty { settings.calendarVisibleIDs = [id] }
        else if settings.calendarVisibleIDs.contains(id) { settings.calendarVisibleIDs.removeAll { $0 == id } }
        else { settings.calendarVisibleIDs.append(id) }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Markdown & sharing") {
                settingRow("Markdown formatting", "Use headings, emphasis, lists, links and code in notes") {
                    Toggle("Markdown formatting", isOn: $settings.markdownEnabled).toggleStyle(.switch).labelsHidden()
                }
                settingRow("Preview after inactivity", "Show formatted Markdown after you stop editing") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { settings.markdownPreviewDelay }, set: { settings.markdownPreviewDelay = $0.rounded() }), in: 1...60)
                            .frame(width: 140).accessibilityLabel("Markdown preview delay")
                        Text("\(Int(settings.markdownPreviewDelay)) s").monospacedDigit().frame(width: 55, alignment: .trailing)
                    }.disabled(!settings.markdownEnabled)
                }
                settingRow("Show Share button", "Share individual notes as Markdown files", divider: false) {
                    Toggle("Show Share button", isOn: $settings.shareNotes).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection("Shortcuts") {
                ForEach(KeyboardAction.allCases, id: \.rawValue) { action in
                    HStack {
                        Text(action.title).font(SettingsPalette.font(13, medium: true))
                        Spacer()
                        Text(action.isGlobal ? "Global" : "In Margin").font(SettingsPalette.font(11)).foregroundStyle(secondaryInk)
                        HStack(spacing: 12) {
                            ShortcutRecorder(shortcut: settings.shortcut(for: action), changed: { settings.setShortcut($0, for: action) })
                                .frame(width: 145, height: 30).background(SettingsPalette.well, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(action.title)
                                .disabled(!settings.shortcutEnabled(action)).opacity(settings.shortcutEnabled(action) ? 1 : 0.4)
                            Toggle("Enable \(action.title)", isOn: Binding(get: { settings.shortcutEnabled(action) }, set: { settings.setShortcutEnabled($0, for: action) }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                    }.frame(height: 39).overlay(alignment: .bottom) { rule.frame(height: action == .close ? 0 : 1) }
                }
            }
            settingRow("Quick capture action", "Choose what the quick capture shortcut opens", divider: false) {
                settingsMenu("Quick capture action", selection: $settings.shortcutAction, options: ShortcutAction.allCases.map { ($0, $0.rawValue) }, width: 200)
            }
            if let error = settings.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red)
            }
            Button("Restore default shortcuts") { settings.shortcuts = [:]; settings.shortcutError = nil }
                .buttonStyle(SettingsButtonStyle()).fixedSize()
        }
    }

    private var cloud: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Sync") {
                settingRow("Sync my notes", "Use a folder in iCloud Drive or another syncing service", divider: settings.cloudSyncEnabled) {
                    Toggle("Sync my notes", isOn: Binding(
                        get: { settings.cloudSyncEnabled },
                        set: { cloudSync.setEnabled($0) }
                    )).toggleStyle(.switch).labelsHidden().tint(accent)
                }
                if settings.cloudSyncEnabled {
                    settingRow("Folder", cloudSync.folderName ?? "Choose where synced notes are stored") {
                        Button(cloudSync.folderName == nil ? "Choose…" : "Change…") { cloudSync.chooseFolder() }
                            .buttonStyle(MatteButtonStyle()).fixedSize()
                    }
                    settingRow("Status", cloudSync.status, divider: false) {
                        if cloudSync.isSyncing {
                            ProgressView().controlSize(.small).frame(width: 67)
                        } else {
                            Button("Sync Now") { cloudSync.requestSync() }.buttonStyle(MatteButtonStyle(width: 67)).fixedSize()
                        }
                    }
                }
            }
            Text("Margin writes one readable Markdown file per note. Local notes stay encrypted on this Mac; files in the sync folder are readable and are never removed when you turn syncing off.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).frame(maxWidth: 470, alignment: .leading)
            if let error = cloudSync.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.red).frame(maxWidth: 470, alignment: .leading)
            }
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Windows") {
                settingRow("Show in Dock", "Turn off to keep Margin in the menu bar only") { Toggle("Show in Dock", isOn: $settings.showInDock).toggleStyle(.switch).labelsHidden().tint(accent) }
                settingRow("Show over full-screen apps", "Keep the deck reachable in full screen") { Toggle("Show over full-screen apps", isOn: $settings.showOverFullScreen).toggleStyle(.switch).labelsHidden().tint(accent) }
                settingRow("Lock notes", "Hide note contents until you authenticate", divider: false) { Toggle("Lock notes", isOn: $settings.lockNotes).toggleStyle(.switch).labelsHidden().tint(accent) }
            }
        }
    }

    private var appearance: some View {
        VStack(spacing: 14) {
            settingRow("Menu bar icon", "Choose the symbol shown in the macOS menu bar") {
                NoteIconPicker(selection: $settings.menuBarIcon, options: NoteIcons.menuBar, label: "Choose menu bar icon")
            }
            notePreview
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme").font(SettingsPalette.font(13, medium: true))
                        HStack(spacing: 12) {
                            ForEach([AppearanceMode.light, .dark, .system], id: \.self) { themeButton($0) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Interface color").font(SettingsPalette.font(13, medium: true))
                            Spacer()
                            Text(settings.interfaceColor.rawValue.capitalized).font(SettingsPalette.font(11)).foregroundStyle(secondaryInk)
                        }
                        HStack(spacing: 12) {
                            ForEach(InterfaceColor.allCases, id: \.self) { value in
                                swatch(Color(nsColor: value.nsColor(isDark: colorScheme == .dark)), selected: settings.interfaceColor == value,
                                       label: "\(value.rawValue.capitalized) interface color") { settings.interfaceColor = value }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("New note color").font(SettingsPalette.font(13, medium: true))
                        Spacer()
                        Text(settings.useDefaultColor ? (settings.defaultColorHex == nil ? settings.defaultColor.name : "Custom") : "Cycle palette")
                            .font(SettingsPalette.font(11)).foregroundStyle(secondaryInk)
                    }.padding(.bottom, 10)
                    HStack(spacing: 10) {
                        Button { settings.useDefaultColor = false } label: {
                            Circle().fill(AngularGradient(colors: NoteColor.allCases.map(\.color), center: .center))
                                .overlay(Image(systemName: "arrow.2.circlepath").font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.7)))
                                .frame(width: 23, height: 23).padding(4)
                                .overlay(Circle().stroke(!settings.useDefaultColor ? accent : .clear, lineWidth: 1.5))
                                .frame(width: 32, height: 32).contentShape(Circle())
                        }.buttonStyle(.plain).help("Cycle through the palette for each new note")
                            .accessibilityLabel("Cycle new note colors").accessibilityValue(!settings.useDefaultColor ? "Selected" : "Not selected")
                        ForEach(NoteColor.allCases, id: \.rawValue) { value in
                        swatch(value.color, selected: settings.useDefaultColor && settings.defaultColorHex == nil && settings.defaultColor == value,
                               label: "\(value.name) default note color") {
                            settings.defaultColor = value; settings.defaultColorHex = nil; settings.useDefaultColor = true
                        }
                    } }
                    ColorPicker("Custom note color", selection: Binding(get: {
                        guard let hex = settings.defaultColorHex else { return settings.defaultColor.color }
                        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
                    }, set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                        settings.defaultColorHex = UInt32((rgb.redComponent * 255).rounded()) << 16 | UInt32((rgb.greenComponent * 255).rounded()) << 8 | UInt32((rgb.blueComponent * 255).rounded())
                        settings.useDefaultColor = true
                    }), supportsOpacity: false)
                    .font(SettingsPalette.font(12)).padding(.top, 12)
                    Text(settings.useDefaultColor ? (settings.defaultColorHex == nil ? "Each new note starts in \(settings.defaultColor.name.lowercased())." : "New notes use a soft tint of your custom color.") : "Each new note gets the next color in the palette.")
                        .font(SettingsPalette.font(11)).foregroundStyle(secondaryInk).padding(.top, 9)
                    compactRow("Note typeface") {
                        settingsMenu("Note typeface", selection: $settings.fontName,
                                     options: Array(Set(noteFontNames + [settings.fontName])).sorted().map { ($0, $0) }, width: 170)
                    }
                    compactRow("Text size") {
                        settingsMenu("Text size", selection: $settings.textSize,
                                     options: Array(Set([10.0, 12.0, 14.0, 16.0, 18.0, 21.0, 24.0, 28.0, settings.textSize])).sorted().map { ($0, "\($0.formatted()) pt") }, width: 100)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private func themeButton(_ value: AppearanceMode) -> some View {
        Button { settings.appearance = value } label: {
            VStack(spacing: 9) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: SettingsPalette.color(value == .dark ? 0x515347 : 0xD7D2C5))).frame(width: 17)
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: SettingsPalette.color(value == .light ? 0xE6E1D6 : 0x45473D)))
                        .padding(.bottom, 9)
                }
                .padding(7).frame(height: 44)
                .background {
                    if value == .system {
                        HStack(spacing: 0) { Color(nsColor: SettingsPalette.color(0xF8F6F0)); Color(nsColor: SettingsPalette.color(0x34352F)) }
                    } else { Color(nsColor: SettingsPalette.color(value == .dark ? 0x34352F : 0xF8F6F0)) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(4).background(SettingsPalette.well, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(settings.appearance == value ? accent : .clear, lineWidth: 1.5))
                Text(value.rawValue.capitalized).font(SettingsPalette.font(11, medium: settings.appearance == value))
                    .foregroundStyle(settings.appearance == value ? accent : secondaryInk)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(value.rawValue.capitalized) theme")
            .accessibilityValue(settings.appearance == value ? "Selected" : "Not selected")
    }

    private func swatch(_ color: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 23, height: 23)
                .overlay(Circle().stroke(.black.opacity(0.08)))
                .padding(4).overlay(Circle().stroke(selected ? accent : .clear, lineWidth: 1.5))
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(selected ? "Selected" : "Not selected").help(label)
    }

    private var notePreview: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [SettingsPalette.shell, SettingsPalette.well], center: .top, startRadius: 5, endRadius: 450)
            HStack {
                Text("Live preview · new note style")
                Spacer()
                Text("\(previewIndex + 1) / 3").monospacedDigit()
            }.font(SettingsPalette.font(11)).foregroundStyle(secondaryInk).padding(16)
            ZStack {
                ForEach(0..<3) { index in
                    previewNote(index)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 24)
        }
        .frame(height: 164).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func previewNote(_ index: Int) -> some View {
        let selected = previewIndex == index
        let left = index == (previewIndex + 1) % 3
        let content = Self.previewContent(notes: store.active, locked: settings.lockNotes, index: index)
        let noteColor = settings.useDefaultColor ? settings.defaultColor : NoteColor.allCases[(store.nextNoteColor.rawValue + index) % NoteColor.allCases.count]
        let previewColor = Note(color: noteColor, presentation: settings.useDefaultColor ? settings.defaultColorHex.map { NotePresentation(colorHex: $0) } : nil).displayColor
        return Button {
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.5)) { previewIndex = index }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(.black.opacity(0.3)).frame(width: 12, height: 12)
                    Circle().fill(.black.opacity(0.12)).frame(width: 12, height: 12)
                    Text(content.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if settings.shareNotes { Image(systemName: "square.and.arrow.up").font(.system(size: 14)) }
                    Image(systemName: "pin").font(.system(size: 14))
                }.padding(.horizontal, 17).frame(height: 45)
                SettingsNoteBody(text: content.body, font: settings.nsNoteFont, markdownEnabled: settings.markdownEnabled)
                    .padding(.horizontal, 17).allowsHitTesting(false).accessibilityHidden(true)
            }
            .foregroundStyle(.black.opacity(0.73))
            .frame(width: 400, height: 244, alignment: .topLeading)
            .background(previewColor, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.09), radius: 12, y: 8)
            .scaleEffect(0.52).frame(width: 208, height: 127)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1 : 0.88).rotationEffect(.degrees(selected ? 0 : (left ? -8 : 8)), anchor: .bottom)
        .offset(x: selected ? 0 : (left ? -137 : 137), y: selected ? 0 : 3)
        .zIndex(selected ? 2 : 1)
        .accessibilityLabel("Preview \(content.title)").accessibilityValue(selected ? "Selected" : "Not selected")
    }

    static func previewContent(notes: [Note], locked: Bool, index: Int) -> (title: String, body: String) {
        if !locked, notes.indices.contains(index) { return (notes[index].title, notes[index].body) }
        let samples = [("Weekend plans", "## A little room to think\n- [ ] Pick up coffee beans\n- [ ] Book the train\n- [x] ~~Call Sam~~"),
                       ("For a quiet hour.", "A book, a window,\nand the phone on silent.\n\n**Make time for it.**"),
                       ("Monday, 10 am.", "Bring the sketches.\nKeep the afternoon free.")]
        return samples[min(max(index, 0), samples.count - 1)]
    }

    private func compactRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(SettingsPalette.font(13, medium: true))
            Spacer(minLength: 8)
            trailing().controlSize(.small)
        }.padding(.top, 8).overlay(alignment: .top) { rule.frame(height: 1) }.padding(.top, 8)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("Application") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Margin").font(SettingsPalette.font(15, medium: true))
                            Text("Version \(versionText)").font(SettingsPalette.font(12)).foregroundStyle(secondaryInk)
                            Text("Sticky notes that live at the edge of your screen.").font(SettingsPalette.font(12)).foregroundStyle(secondaryInk)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            settingsSection("Updates") {
                settingRow("Automatic updates", "Check, download, and install new versions automatically") {
                    Toggle("Automatic updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0; updater.automaticallyDownloadsUpdates = $0 }
                    )).toggleStyle(.switch).labelsHidden().tint(accent)
                }
                settingRow("Check now", "Look for a new version manually", divider: false) {
                    Button("Check Now") { updater.checkForUpdates() }.buttonStyle(SettingsButtonStyle()).fixedSize()
                }
            }
            settingsSection("Privacy & legal") {
                HStack(spacing: 12) {
                    Button("Privacy policy") { openLegal("PRIVACY") }
                    Button("License & use") { openLegal("TERMS") }
                    Menu("More documents") {
                        Button("Data deletion & backups") { openLegal("DATA-DELETION") }
                        Button("Security policy") { openLegal("SECURITY") }
                        Button("Third-party notices") { openLegal("THIRD-PARTY-NOTICES") }
                        Button("MIT License") { openLegal("LICENSE") }
                    }.menuStyle(.borderlessButton).fixedSize()
                }.buttonStyle(SettingsButtonStyle())
            }
        }
    }

    private func openLegal(_ name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Legal") {
            NSWorkspace.shared.open(url)
        } else { store.errorMessage = "The legal document is missing from this build." }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return Self.visibleVersion(shortVersion: version)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(title)
    }
    private func settingRow<Trailing: View>(_ title: String, _ subtitle: String, divider: Bool = true, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsPalette.font(13, medium: true))
                Text(subtitle).font(SettingsPalette.font(12)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing().fixedSize().controlSize(.small)
        }.padding(.vertical, 6).overlay(alignment: .bottom) { rule.frame(height: divider ? 1 : 0) }
    }

    private func settingsMenu<Value: Hashable>(_ title: String, selection: Binding<Value>, options: [(Value, String)], width: CGFloat) -> some View {
        SettingsMenu(title: title, selection: selection, options: options)
            .padding(.leading, 9).padding(.trailing, 26).frame(width: width, height: 30)
            .background(SettingsPalette.well, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(secondaryInk)
                    .padding(.trailing, 11).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let finish: (Bool) -> Void
    @State private var step = 0
    @State private var login = true
    private let titles = ["Notes stay within reach", "Fan the deck from any edge", "Write without breaking focus", "Find every note in one place"]
    private let bodies = [
        "Margin keeps a compact deck at the side or bottom of your screen. Each color marks a different note, ready when you need it and quiet when you do not.",
        "Move the pointer to your chosen edge and the deck opens. Hover a note for a quick preview, or click it to start writing.",
        "Notes open where you left them and save as you type. Checklists, links, colors, and pinning are always close at hand.",
        "All Notes brings active and archived work together. Search every title and line, then restore completed notes whenever you need them."
    ]
    private let keys = ["Any screen edge", "Hover or click", "⌥⌘N", "⌥⌘L"]
    private let hints = ["choose the placement in Settings", "preview without leaving your work", "creates a note from anywhere", "opens your full library"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome · \(step + 1) of 4").font(.system(size: 12, weight: .semibold)).foregroundStyle(appAccent).padding(.top, 58)
                Text(titles[step]).font(.system(size: 27, weight: .bold)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 15)
                Text(bodies[step]).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(7).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 11)
                HStack { Text(keys[step]).font(.system(size: 12, weight: .medium, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 7).background(appAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7)); Text(hints[step]).font(.caption).foregroundStyle(.secondary) }.padding(.top, 17)
                if step == 3 { Toggle(isOn: $login) { VStack(alignment: .leading) { Text("Add to Login Items"); Text("Open automatically at sign-in").font(.caption).foregroundStyle(.secondary) } }.toggleStyle(.checkbox).tint(appAccent).padding(12).modifier(SurfaceCard()).padding(.top, 20) }
                Spacer()
                HStack {
                    HStack(spacing: 7) { ForEach(0..<4) { index in Button { step = index } label: { Capsule().fill(index == step ? appAccent : Color.secondary.opacity(0.25)).frame(width: index == step ? 22 : 6, height: 6).frame(height: 20) }.buttonStyle(.plain).accessibilityLabel("Step \(index + 1)") } }
                    Spacer()
                    if step < 3 { Button("Skip") { finish(login) }.buttonStyle(HoverButtonStyle()).foregroundStyle(.secondary); Button("Continue") { step += 1 }.buttonStyle(MatteButtonStyle(fill: appAccent, foreground: appAccentForeground)) }
                    else { Button("Create my first note") { finish(login) }.buttonStyle(MatteButtonStyle(fill: appAccent, foreground: appAccentForeground)) }
                }.padding(.bottom, 22)
            }
            .padding(.horizontal, 26).frame(width: 360)
            ZStack {
                appAccent.opacity(0.08)
                Circle().fill(appAccent.opacity(0.10)).frame(width: 320, height: 320)
                onboardingArt.id(step).transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 13)).padding(1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: step)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var onboardingArt: some View {
        switch step {
        case 0:
            artSurface {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Image(systemName: "rectangle.righthalf.inset.filled").foregroundStyle(appAccent); Text("Margin").font(.system(size: 13, weight: .semibold)); Spacer(); Text("Ready").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) { Text("Your thoughts, nearby").font(.system(size: 18, weight: .bold)); Text("A quiet deck that appears when you reach for it.").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 175, alignment: .leading) }
                        Spacer()
                        VStack(spacing: 6) { ForEach(NoteColor.allCases, id: \.rawValue) { Capsule().fill($0.color).frame(width: 7, height: 20) } }.padding(9).background(.black.opacity(0.48), in: Capsule())
                    }
                    Spacer()
                }
            }
        case 1:
            ZStack(alignment: .trailing) {
                artSurface { VStack(alignment: .leading) { Label("Preview the deck", systemImage: "cursorarrow").font(.system(size: 13, weight: .semibold)).foregroundStyle(appAccent); Spacer() } }
                ForEach(Array(NoteColor.allCases.prefix(3).enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 12).fill(value.color).frame(width: 190, height: 82)
                        .overlay(alignment: .topLeading) { Text(["Launch notes", "Today", "Reading list"][index]).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.72)).padding(12) }
                        .shadow(color: .black.opacity(0.13), radius: 6, y: 3).offset(x: CGFloat(index * 22 - 12), y: CGFloat(index * 45 - 30))
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(.red.opacity(0.72)).frame(width: 9, height: 9); Circle().fill(.black.opacity(0.10)).frame(width: 9, height: 9); Text("Launch notes").font(.system(size: 13, weight: .semibold)); Spacer(); Text("Saved").font(.caption).foregroundStyle(.black.opacity(0.45)); Image(systemName: "pin.fill").foregroundStyle(.black.opacity(0.42)) }
                Divider().opacity(0.35)
                Text("Polish onboarding\nReview launch checklist\nShare the build").font(.custom("Virgil", size: 19)).lineSpacing(7)
                Spacer()
                HStack { ForEach(NoteColor.allCases, id: \.rawValue) { RoundedRectangle(cornerRadius: 4).fill($0.color).frame(width: 18, height: 18) }; Spacer(); Image(systemName: "checklist").foregroundStyle(appAccent) }
            }.padding(17).frame(width: 290, height: 250).foregroundStyle(.black.opacity(0.74)).background(NoteColor.amber.color, in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        default:
            artSurface {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); Text("Search notes").font(.caption).foregroundStyle(.secondary) }.padding(7).background(appSearch, in: RoundedRectangle(cornerRadius: 7))
                        ForEach(["Launch notes", "Reading list", "Weekend"], id: \.self) { title in Text(title).font(.system(size: 11, weight: title == "Launch notes" ? .semibold : .regular)).padding(7).frame(maxWidth: .infinity, alignment: .leading).background(title == "Launch notes" ? appAccent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7)) }
                    }.frame(width: 118)
                    Divider().padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 10) { Text("Launch notes").font(.system(size: 15, weight: .bold)); Text("Everything is saved and searchable.").font(.custom("Virgil", size: 17)); Spacer(); Label("Active", systemImage: "circle.fill").font(.caption).foregroundStyle(appAccent) }
                }
            }
        }
    }

    private func artSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(18).frame(width: 300, height: 250, alignment: .topLeading).modifier(SurfaceCard())
    }
}
