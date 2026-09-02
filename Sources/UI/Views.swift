import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

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
private let appAccent = Color.primary
private let appAccentForeground = Color(nsColor: .windowBackgroundColor)

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

extension AppSettings {
    var noteFont: Font { fontName == "Helvetica" ? .system(size: textSize) : .custom(fontName, size: textSize) }
    var listFont: Font { fontName == "Helvetica" ? .system(size: 13) : .custom(fontName, size: 13) }
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

private final class DragHandleNSView: NSView {
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push(); defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        for row in 0..<3 { for column in 0..<2 {
            NSBezierPath(ovalIn: NSRect(x: 5 + column * 4, y: 7 + row * 4, width: 2, height: 2)).fill()
        } }
    }
}

private struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ view: DragHandleNSView, context: Context) {}
}

private struct ChecklistPreviewLine: View {
    let line: String
    var checkboxSize: CGFloat = 15

    var body: some View {
        if let item = ChecklistLine.parse(line) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: checkboxSize / 4)
                    .fill(item.checked ? Color.black.opacity(0.48) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: checkboxSize / 4).stroke(.black.opacity(0.36), lineWidth: 1.2))
                    .overlay { if item.checked { Image(systemName: "checkmark").font(.system(size: checkboxSize * 0.6, weight: .bold)).foregroundStyle(.white) } }
                    .frame(width: checkboxSize, height: checkboxSize).padding(.top, 1)
                Text(item.text).foregroundStyle(.black.opacity(item.checked ? 0.44 : 0.72)).strikethrough(item.checked)
            }
        } else {
            Text(line.isEmpty ? " " : line)
        }
    }
}

struct EdgeDeckView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: EdgePanelModel
    let expand: (Bool) -> Void
    let create: () -> Void
    let open: (UUID) -> Void
    let showAll: () -> Void
    let showArchive: () -> Void
    let showSettings: () -> Void
    @State private var hovered: UUID?
    @State private var dragging: UUID?
    @State private var hoverReadyAt = 0.0
    @State private var plusHovered = false

    var body: some View {
        ZStack(alignment: settings.side == .bottom ? .bottom : (settings.side == .right ? .trailing : .leading)) {
            Color.clear
            if settings.side == .bottom {
                if model.expanded || settings.keepOpen { bottomFan } else { bottomPill }
            } else if model.expanded || settings.keepOpen {
                fan
            } else {
                pill
            }
            if let undo = store.undoNote {
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
                ForEach(Array(store.active.prefix(8))) { note in
                    Capsule().fill(note.color.color).frame(width: 16, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.48), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { expand(true) } }
        .contextMenu { deckMenu }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("Show Margin deck")
    }

    private var bottomFan: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(store.active.prefix(8).enumerated()), id: \.element.id) { index, note in
                bottomSlot(note, index: index)
                    .onDrag { dragging = note.id; return NSItemProvider(object: note.id.uuidString as NSString) }
                    .onDrop(of: [.text], delegate: NoteDropDelegate(target: note.id, dragging: $dragging, store: store))
            }
            deckAddButton.padding(.bottom, 2)
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { expand(true) } else { hovered = nil; expand(false) }
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
                        Text(current.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        ForEach(Array(current.body.components(separatedBy: "\n").prefix(4).enumerated()), id: \.offset) { _, line in
                            ChecklistPreviewLine(line: line, checkboxSize: 11).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(settings.noteFont).foregroundStyle(.black.opacity(0.72))
                    .padding(12).frame(width: DeckCardMetrics.contentWidth, height: DeckCardMetrics.height, alignment: .topLeading)
                    .background(current.color.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .modifier(CardShadow(lifted: true))
                    .padding(.bottom, 34)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                Text(current.title.isEmpty ? "Untitled note" : current.title)
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(.black.opacity(0.66)).padding(.horizontal, 9)
                    .frame(width: DeckCardMetrics.bottomStep - 7, height: 30)
                    .background(current.color.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .frame(width: DeckCardMetrics.bottomStep, height: 210, alignment: .bottom)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active where settings.fanMode == .hover && DeckHoverGate.isReady(now: ProcessInfo.processInfo.systemUptime, readyAt: hoverReadyAt): hovered = note.id
            case .ended where settings.fanMode == .hover && hovered == note.id: hovered = nil
            default: break
            }
        }
        .contextMenu { noteMenu(current) }
        .zIndex(lifted ? 20 : Double(index))
        .animation(reduceMotion ? nil : .easeOut(duration: settings.cardDuration), value: lifted)
        .accessibilityLabel("\(current.title), \(current.color.name)")
    }

    private var pill: some View {
        VStack(spacing: 5) {
            if store.active.isEmpty {
                Button(action: create) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Add note")
            } else {
                Button { expand(true) } label: {
                    VStack(spacing: 6) {
                        ForEach(Array(store.active.prefix(8))) { note in
                            Capsule().fill(note.color.color).frame(width: 6, height: 16)
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 9)
                    .background(.black.opacity(0.48), in: Capsule())
                    .shadow(color: .black.opacity(0.24), radius: 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { expand(true) } }
                .contextMenu { deckMenu }
                .accessibilityLabel("Show Margin deck")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.side == .right ? .trailing : .leading)
    }

    private var fan: some View {
        let notes = Array(store.active.prefix(8))
        let hoveredIndex = notes.firstIndex { $0.id == hovered }
        return VStack(alignment: settings.side == .right ? .trailing : .leading, spacing: DeckCardMetrics.spacing) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                deckCard(note, index: index)
                    .onDrag { dragging = note.id; return NSItemProvider(object: note.id.uuidString as NSString) }
                    .onDrop(of: [.text], delegate: NoteDropDelegate(target: note.id, dragging: $dragging, store: store))
                    .offset(y: DeckCardMetrics.spreadOffset(index: index, hoveredIndex: hoveredIndex))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            }
            if store.active.count > 8 {
                Button("+\(store.active.count - 8) more") { showAll() }
                    .buttonStyle(.borderless).padding(8).background(.regularMaterial, in: Capsule()).padding(.top, 90)
            } else {
                deckAddButton
                    .padding(.top, 88)
                    .opacity(model.fanVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .timingCurve(0.20, 1.08, 0.30, 1.00, duration: settings.fanDuration).delay(Double(min(store.active.count, 8)) * 0.03 * settings.animationScale), value: model.fanVisible)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.side == .right ? .trailing : .leading)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                expand(true)
            } else {
                hovered = nil
                expand(false)
            }
        }
        .onAppear { hovered = nil; hoverReadyAt = ProcessInfo.processInfo.systemUptime + settings.fanDuration }
        .onDisappear { hovered = nil }
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
        .animation(reduceMotion ? nil : .timingCurve(0.20, 1.00, 0.30, 1.00, duration: 0.20 * settings.animationScale), value: plusHovered)
        .zIndex(20)
        .accessibilityLabel("Add")
    }

    private func deckCard(_ note: Note, index: Int) -> some View {
        let current = store.note(note.id) ?? note
        let lifted = hovered == note.id
        let activeOffset = lifted ? DeckCardMetrics.liftedOffset : DeckCardMetrics.tuckedOffset(index: index)
        let offset = reduceMotion || model.fanVisible ? activeOffset : DeckCardMetrics.hiddenOffset
        let isLast = index == min(store.active.count, 8) - 1
        let edge: Alignment = settings.side == .right ? .trailing : .leading
        return Button { activate(note, lifted: lifted) } label: {
            ZStack(alignment: edge) {
                HStack(spacing: 0) {
                if settings.side == .right { tabLabel(current.title) }
                VStack(alignment: settings.side == .right ? .leading : .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        if settings.side == .right {
                            Text(current.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(shortAge(current.updatedAt)).font(.system(size: 9)).foregroundStyle(.black.opacity(0.42))
                        } else {
                            Text(shortAge(current.updatedAt)).font(.system(size: 9)).foregroundStyle(.black.opacity(0.42))
                            Spacer(minLength: 0)
                            Text(current.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                    }
                    VStack(alignment: settings.side == .right ? .leading : .trailing, spacing: 3) {
                        ForEach(Array(current.body.components(separatedBy: "\n").prefix(3).enumerated()), id: \.offset) { _, line in
                            ChecklistPreviewLine(line: line, checkboxSize: 11).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: settings.side == .right ? .leading : .trailing)
                        }
                    }
                    .font(settings.noteFont).foregroundStyle(.black.opacity(0.72))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(width: DeckCardMetrics.contentWidth, height: DeckCardMetrics.height, alignment: .topLeading)
                if settings.side == .left { tabLabel(current.title) }
            }
            .frame(width: DeckCardMetrics.width, height: DeckCardMetrics.height)
            .foregroundStyle(.black.opacity(0.73))
            .background(current.color.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(CardShadow(lifted: lifted))
            .rotationEffect(.degrees(settings.side == .right ? -2.2 : 2.2))
            .offset(x: settings.side == .right ? offset : -offset)
            .opacity(model.fanVisible ? 1 : (reduceMotion ? 0 : 1))
                .animation(reduceMotion ? nil : .timingCurve(0.20, 1.05, 0.30, 1.00, duration: settings.cardDuration), value: lifted)
                .animation(reduceMotion ? nil : .timingCurve(0.20, 1.08, 0.30, 1.00, duration: settings.fanDuration).delay(Double(index) * 0.03 * settings.animationScale), value: model.fanVisible)
            }
        }
        .buttonStyle(.plain)
        .frame(width: DeckCardMetrics.visibleWidth, height: DeckCardMetrics.height, alignment: edge)
        .overlay(alignment: settings.side == .right ? .topTrailing : .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .frame(
                    width: DeckCardMetrics.hoverWidth(lifted: lifted, index: index),
                    height: DeckCardMetrics.hoverHeight(lifted: lifted, isLast: isLast)
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active where settings.fanMode == .hover && DeckHoverGate.isReady(now: ProcessInfo.processInfo.systemUptime, readyAt: hoverReadyAt): hovered = note.id
                    case .ended where settings.fanMode == .hover && hovered == note.id: hovered = nil
                    default: break
                    }
                }
                .onTapGesture { activate(note, lifted: lifted) }
        }
        .zIndex(Double(index))
        .contextMenu { noteMenu(current) }
        .accessibilityLabel("\(current.title), \(current.color.name), edited \(current.updatedAt.formatted(date: .omitted, time: .shortened))")
    }

    private func activate(_ note: Note, lifted: Bool) {
        if DeckHoverGate.opensOnTap(mode: settings.fanMode, alreadyPreviewed: lifted) { open(note.id) }
        else { hovered = note.id }
    }

    private func tabLabel(_ title: String) -> some View {
        Text(title.isEmpty ? "Untitled note" : title)
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.58))
            .lineLimit(1).truncationMode(.tail)
            .frame(width: DeckCardMetrics.height - 28)
            .rotationEffect(.degrees(settings.side == .right ? -90 : 90))
            .frame(width: DeckCardMetrics.tabWidth, height: DeckCardMetrics.height - 20)
            .padding(.top, 10).frame(width: DeckCardMetrics.tabWidth, height: DeckCardMetrics.height, alignment: .top)
            .overlay(alignment: settings.side == .right ? .trailing : .leading) {
                Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: DeckCardMetrics.height - 24)) }
                    .stroke(.black.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: 1, height: DeckCardMetrics.height - 24).padding(.vertical, 12)
            }
    }

    @ViewBuilder private func noteMenu(_ note: Note) -> some View {
        Menu { ForEach(NoteColor.allCases, id: \.rawValue) { value in
            Button { var copy = note; copy.color = value; store.update(copy, immediate: true) } label: {
                HStack { Image(nsImage: value.menuImage); Text(value.name); if note.color == value { Image(systemName: "checkmark") } }
            }
        } } label: { Label("Color", systemImage: "paintpalette") }
        Button { var copy = note; copy.pinned.toggle(); store.update(copy, immediate: true); if copy.pinned { open(copy.id) } } label: {
            Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
        }
        Button { if let copy = store.duplicate(note.id) { open(copy.id) } } label: { Label("Duplicate", systemImage: "doc.on.doc") }
        Menu {
            Button { settings.side = .left } label: { Label("Left", systemImage: "rectangle.lefthalf.inset.filled") }
            Button { settings.side = .right } label: { Label("Right", systemImage: "rectangle.righthalf.inset.filled") }
            Button { settings.side = .bottom } label: { Label("Bottom", systemImage: "rectangle.bottomhalf.inset.filled") }
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
            Button("Left") { settings.side = .left }
            Button("Right") { settings.side = .right }
            Button("Bottom") { settings.side = .bottom }
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
    static let hoverSpread: CGFloat = 24
    static let bottomStep: CGFloat = 104

    static func tuckedOffset(index: Int) -> CGFloat { width - tabWidth - CGFloat(index * 4) }
    static func hoverWidth(lifted: Bool, index: Int) -> CGFloat { lifted ? visibleWidth : tabWidth + CGFloat(index * 4) }
    static func hoverHeight(lifted: Bool, isLast: Bool) -> CGFloat { lifted || isLast ? height : step }
    static func spreadOffset(index: Int, hoveredIndex: Int?) -> CGFloat { hoveredIndex.map { index > $0 ? hoverSpread : 0 } ?? 0 }
}

private struct NoteDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let store: NotesStore
    func dropEntered(info: DropInfo) { if let dragging, dragging != target { store.move(dragging, before: target) } }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

final class ChecklistNSTextView: NSTextView {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    var changed: ((String) -> Void)?
    var cancelled: (() -> Void)?
    var noteFont: NSFont = .systemFont(ofSize: 21)

    override func didChangeText() {
        super.didChangeText(); applyStyle(); changed?(string); needsDisplay = true
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let value = (insertString as? NSAttributedString)?.string ?? insertString as? String
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if value == "]", range.length == 0,
           let shortcut = Self.checklistShortcutRange(in: string, before: range.location) {
            super.insertText("- [ ] ", replacementRange: shortcut)
            return
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

    static func opensLink(with modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private var normalTypingAttributes: [NSAttributedString.Key: Any] {
        [.font: noteFont, .foregroundColor: NSColor.black.withAlphaComponent(0.76)]
    }

    func applyStyle() {
        guard let storage = textStorage else { return }
        let selection = selectedRanges
        selectedTextAttributes = [
            .backgroundColor: NSColor.black.withAlphaComponent(0.14),
            .foregroundColor: NSColor.black.withAlphaComponent(0.88)
        ]
        storage.beginEditing()
        storage.setAttributes(normalTypingAttributes, range: NSRange(location: 0, length: storage.length))
        (string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (string as NSString).length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            if range.length >= 6 {
                let prefix = (self.string as NSString).substring(with: NSRange(location: range.location, length: 6)).lowercased()
                if prefix == "- [ ] " || prefix == "- [x] " {
                    let marker = NSRange(location: range.location, length: 6)
                    let paragraph = NSMutableParagraphStyle(); paragraph.firstLineHeadIndent = 18; paragraph.headIndent = 18
                    paragraph.minimumLineHeight = self.layoutManager?.defaultLineHeight(for: self.noteFont)
                        ?? ceil(self.noteFont.ascender - self.noteFont.descender + self.noteFont.leading)
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)], range: marker)
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
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
        for (url, range) in Self.links(in: string) {
            storage.addAttributes([.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
        }
        storage.endEditing(); selectedRanges = selection
        typingAttributes = normalTypingAttributes
        insertionPointColor = NSColor.black.withAlphaComponent(0.76)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            self.applyStyle()
            self.needsDisplay = true
            window.makeFirstResponder(self)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
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

    override func draw(_ dirtyRect: NSRect) {
        guard let layoutManager, let textContainer else { super.draw(dirtyRect); return }
        super.draw(dirtyRect)
        let ns = string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard range.length >= 6 else { return }
            let prefix = ns.substring(with: NSRange(location: range.location, length: 6)).lowercased()
            guard prefix == "- [ ] " || prefix == "- [x] " else { return }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var rect = lineRect
            rect.origin.x = self.textContainerInset.width + 1
            rect.origin.y += self.textContainerInset.height + 6
            rect.size = NSSize(width: 16, height: 16)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5.5, yRadius: 5.5)
            NSColor.black.withAlphaComponent(0.42).setStroke(); path.lineWidth = 1.5; path.stroke()
            if prefix == "- [x] " {
                NSColor.black.withAlphaComponent(0.52).setFill(); path.fill()
                let mark = NSBezierPath(); mark.move(to: NSPoint(x: rect.minX + 3.5, y: rect.midY)); mark.line(to: NSPoint(x: rect.midX - 0.5, y: rect.minY + 4)); mark.line(to: NSPoint(x: rect.maxX - 3, y: rect.maxY - 4))
                NSColor.white.setStroke(); mark.lineWidth = 1.8; mark.stroke()
            }
            _ = textContainer
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager, let textContainer, !string.isEmpty {
            var local = point; local.x -= textContainerInset.width; local.y -= textContainerInset.height
            let glyph = min(layoutManager.glyphIndex(for: local, in: textContainer), max(0, layoutManager.numberOfGlyphs - 1))
            let character = layoutManager.characterIndexForGlyph(at: glyph)
            let line = (string as NSString).lineRange(for: NSRange(location: min(character, (string as NSString).length - 1), length: 0))
            if line.length >= 6 {
                let prefix = (string as NSString).substring(with: NSRange(location: line.location, length: 6)).lowercased()
                let lineGlyph = layoutManager.glyphIndexForCharacter(at: line.location)
                let rect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyph, effectiveRange: nil).offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                if (prefix == "- [ ] " || prefix == "- [x] "), point.x <= rect.minX + 22 {
                    let lineText = (string as NSString).substring(with: line)
                    let contentRange = NSRange(location: line.location, length: line.length - (lineText.hasSuffix("\n") ? 1 : 0))
                    if let replacement = ChecklistLine.toggled((string as NSString).substring(with: contentRange)) {
                        textStorage?.replaceCharacters(in: contentRange, with: replacement); didChangeText(); return
                    }
                }
            }
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).insetBy(dx: -2, dy: -2)
            if glyphRect.contains(local), Self.opensLink(with: event.modifierFlags),
               let url = textStorage?.attribute(.link, at: character, effectiveRange: nil) as? URL {
                NSWorkspace.shared.open(url); return
            }
        }
        super.mouseDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { cancelled?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelled?(); return }
        super.keyDown(with: event)
    }
}

final class ChecklistEditorHandle: ObservableObject {
    weak var view: ChecklistNSTextView?
    func insertItem() { view?.insertChecklistItem() }
}

struct ChecklistTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let cancel: () -> Void
    let handle: ChecklistEditorHandle

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.focusRingType = .none; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = ChecklistNSTextView(); view.drawsBackground = false; view.isRichText = false; view.allowsUndo = true; view.usesFindPanel = true; view.isIncrementalSearchingEnabled = true; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.focusRingType = .none; view.textContainerInset = NSSize(width: 0, height: 8); view.textContainer?.widthTracksTextView = true; view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.noteFont = font; view.string = text; view.applyStyle(); view.cancelled = cancel; view.changed = { value in if value != text { text = value } }
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
        view.noteFont = font; view.cancelled = cancel
        if textChanged { view.string = text }
        if textChanged || fontChanged { view.applyStyle(); view.needsDisplay = true }
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
                        }.frame(width: 9, height: 9)
                        Circle().fill(.black.opacity(0.12)).frame(width: 9, height: 9)
                    }.frame(width: 29, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain).onHover { closeHovered = $0 }.animation(.easeOut(duration: 0.10), value: closeHovered)
                .accessibilityLabel("Close note").help("Close this note and return to the deck")
                TextField("Untitled note", text: $note.title).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Saved · \(shortAge(note.updatedAt))").font(.system(size: 11)).foregroundStyle(.black.opacity(0.42))
                DragHandle().frame(width: 18, height: 24).help("Drag to move; drag an edge or corner to resize")
                Button { note.pinned.toggle(); save(immediate: true); pin(note.pinned) } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
                        .background(note.pinned ? .black.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(HoverButtonStyle()).foregroundStyle(.black.opacity(0.48)).help(note.pinned ? "Unpin from desktop" : "Pin note to desktop")
            }
            .padding(.horizontal, 16).frame(height: 47)
            Divider().opacity(0.22).padding(.horizontal, 16)
            ChecklistTextEditor(text: $note.body, font: settings.nsNoteFont, cancel: close, handle: checklistEditor).padding(.horizontal, 17)
            Divider().opacity(0.2)
            HStack(spacing: 8) {
                ForEach(NoteColor.allCases, id: \.rawValue) { value in
                    Button { note.color = value; save(immediate: true) } label: {
                        RoundedRectangle(cornerRadius: 6).fill(value.color).frame(width: 20, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(colorScheme == .dark ? .white.opacity(note.color == value ? 0.72 : 0) : .black.opacity(note.color == value ? 0.48 : 0), lineWidth: 2.5).padding(-5))
                    }.buttonStyle(HoverButtonStyle()).help("\(value.name) color")
                }
                Button(action: checklistEditor.insertItem) {
                    Image(systemName: "checklist").frame(width: 25, height: 25)
                }
                .buttonStyle(HoverButtonStyle()).accessibilityLabel("Add checklist item").help("Add a checklist item")
                Spacer()
                Button("Delete", role: .destructive, action: delete).buttonStyle(MatteButtonStyle(fill: .red.opacity(0.13), foreground: Color(red: 0.62, green: 0.08, blue: 0.06), width: 58)).fixedSize()
                Button("Mark complete", action: archive).buttonStyle(MatteButtonStyle(fill: .black.opacity(0.15), foreground: .black.opacity(0.78), width: 100)).fixedSize()
                Button("Close", action: close).buttonStyle(MatteButtonStyle(fill: .black.opacity(0.10), foreground: .black.opacity(0.78), width: 53)).fixedSize()
                Button("") { cycleColor() }.keyboardShortcut(".", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                Button("") { delete() }.keyboardShortcut(.delete, modifiers: .command).frame(width: 0, height: 0).opacity(0)
            }
            .padding(.horizontal, 16).frame(height: 51)
        }
        .foregroundStyle(.black.opacity(0.73))
        .background(note.color.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: note.title) { _ in save() }
        .onChange(of: note.body) { _ in save() }
        .onChange(of: store.notes) { _ in if let fresh = store.note(noteID), fresh.updatedAt > note.updatedAt { note = fresh } }
        .onExitCommand(perform: close)
    }

    private func cycleColor() {
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
        Button(value.rawValue) { filter = value; focused = nil; selected.removeAll() }
            .buttonStyle(HoverButtonStyle()).font(.system(size: 12, weight: filter == value ? .semibold : .regular))
            .foregroundStyle(filter == value ? appAccent : .secondary)
            .padding(.horizontal, 11).frame(height: 27)
            .background(filter == value ? appAccent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Button { if selected.contains(note.id) { selected.remove(note.id) } else { selected.insert(note.id); focused = note.id } } label: {
                RoundedRectangle(cornerRadius: 5).fill(selected.contains(note.id) ? appAccent : .clear).frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(selected.contains(note.id) ? 0 : 0.22), lineWidth: 1.5))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(appAccentForeground).opacity(selected.contains(note.id) ? 1 : 0))
            }.buttonStyle(HoverButtonStyle()).accessibilityLabel(selected.contains(note.id) ? "Deselect \(note.title)" : "Select \(note.title)")
            Capsule().fill(note.color.color).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text(note.archivedAt == nil ? "ACTIVE" : "ARCHIVED").font(.system(size: 9, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5)); Text(shortAge(note.updatedAt)).font(.caption2).foregroundStyle(.secondary) }
                ChecklistPreviewLine(line: note.body.components(separatedBy: "\n").first ?? "", checkboxSize: 10)
                    .font(store.settings.listFont).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 7).contentShape(Rectangle())
        .background((focused == note.id || selected.contains(note.id)) ? appAccent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func previewPane(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundedRectangle(cornerRadius: 3).fill(note.color.color).frame(width: 9, height: 9)
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
                .background(note.color.color, in: RoundedRectangle(cornerRadius: 11)).modifier(CardShadow())
                .offset(x: CGFloat(index) * 18, y: CGFloat(index) * 5)
            }
        }
    }

    private func exportOption(_ format: ExportFormat) -> some View {
        Button { exportFormat = format } label: {
            HStack(spacing: 9) {
                Circle().stroke(.black.opacity(0.24), lineWidth: 1.5).frame(width: 15, height: 15)
                    .overlay(Circle().fill(appAccent).frame(width: 7, height: 7).opacity(exportFormat == format ? 1 : 0))
                Text(format.title).font(.system(size: 12, weight: .semibold)); Text("— \(format.detail)").font(.caption).foregroundStyle(.secondary); Spacer()
            }.padding(.horizontal, 10).frame(height: 34).background(exportFormat == format ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(HoverButtonStyle())
    }
}

struct NotePreview: View {
    let note: Note
    @ObservedObject var settings: AppSettings
    var height: CGFloat = 336
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(note.title).font(.system(size: 17, weight: .bold)); Spacer(); Text("edited \(note.updatedAt.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.black.opacity(0.46)) }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(note.body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        ChecklistPreviewLine(line: line)
                    }
                }
                .font(settings.noteFont).foregroundStyle(.black.opacity(0.72)).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider().opacity(0.25)
            Text(metadata).font(.caption).foregroundStyle(.black.opacity(0.46))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .foregroundStyle(.black.opacity(0.76))
        .background(note.color.color, in: RoundedRectangle(cornerRadius: 18)).modifier(CardShadow(lifted: true))
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
                            RoundedRectangle(cornerRadius: 3).fill(note.color.color).frame(width: 9, height: 9)
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
            Capsule().fill(note.color.color).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text(shortAge(note.archivedAt ?? note.updatedAt)).font(.caption2).foregroundStyle(.secondary) }
                ChecklistPreviewLine(line: note.body.components(separatedBy: "\n").first ?? "", checkboxSize: 10)
                    .font(store.settings.listFont).lineLimit(1).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 7).padding(.horizontal, 7).contentShape(Rectangle())
            .background(focused == note.id ? appAccent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
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

private enum SettingsTab: String, CaseIterable { case general = "General", notes = "Notes", cloud = "Cloud Sync", shortcuts = "Shortcuts", system = "System", appearance = "Appearance", about = "About" }

private final class ShortcutRecorderButton: NSButton {
    var shortcut = GlobalShortcut.standard { didSet { if !recording { title = shortcut.display } } }
    var changed: ((GlobalShortcut) -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bezelStyle = .rounded; target = self; action = #selector(beginRecording); title = shortcut.display
        toolTip = "Click, then press a shortcut"
    }

    @objc private func beginRecording() {
        recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self)
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
              !(event.keyCode == UInt16(kVK_ANSI_L) && modifiers == UInt32(cmdKey | optionKey)),
              let key = Self.keyName(event) else { NSSound.beep(); return }
        shortcut = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        recording = false; title = shortcut.display; changed?(shortcut)
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
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let view = ShortcutRecorderButton(); view.shortcut = shortcut
        view.changed = { context.coordinator.shortcut.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderButton, context: Context) { view.shortcut = shortcut }
    func makeCoordinator() -> Coordinator { Coordinator(shortcut: $shortcut) }

    final class Coordinator {
        var shortcut: Binding<GlobalShortcut>
        init(shortcut: Binding<GlobalShortcut>) { self.shortcut = shortcut }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var cloudSync: CloudSyncController
    @State private var tab = SettingsTab.general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                sidebarHeading("Settings")
                tabButton(.general, "slider.horizontal.3")
                tabButton(.notes, "note.text")
                tabButton(.cloud, "icloud")
                tabButton(.shortcuts, "command")
                tabButton(.system, "laptopcomputer")
                tabButton(.appearance, "paintpalette")
                Divider().opacity(0.4).padding(.vertical, 10)
                sidebarHeading("Info")
                tabButton(.about, "info.circle")
                Spacer()
                Text("Margin \(versionText)").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            .padding(18).frame(width: 196, alignment: .leading).background(appSidebar)
            Divider().opacity(0.45)
            ScrollView { Group { switch tab { case .general: general; case .notes: notes; case .cloud: cloud; case .shortcuts: shortcuts; case .system: system; case .appearance: appearance; case .about: about } }.padding(.horizontal, 40).padding(.vertical, 34).frame(maxWidth: .infinity, alignment: .leading) }
                .background(Color(nsColor: .textBackgroundColor))
        }
        .tint(appAccent)
    }

    private func sidebarHeading(_ title: String) -> some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 5) }

    private func tabButton(_ value: SettingsTab, _ icon: String) -> some View {
        Button { tab = value } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(value.rawValue).font(.system(size: 13, weight: tab == value ? .semibold : .regular))
            }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 36)
                .background(tab == value ? Color.primary.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HoverButtonStyle())
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("General", "How the deck looks and behaves.")
            settingsSection("Deck") {
                settingRow("Screen side", "Which edge the deck lives on") { Picker("", selection: $settings.side) { Text("Left").tag(ScreenSide.left); Text("Right").tag(ScreenSide.right); Text("Bottom").tag(ScreenSide.bottom) }.pickerStyle(.segmented).frame(width: 190) }
                settingRow("Fan notes", "Hovering always fans the deck; this is what opens a card") { Picker("", selection: $settings.fanMode) { Text("On hover").tag(FanMode.hover); Text("On click").tag(FanMode.click) }.pickerStyle(.segmented).frame(width: 160) }
                settingRow("Keep the deck open", "The deck stays at the edge instead of resting as the dots") { Toggle("Keep the deck open", isOn: $settings.keepOpen).toggleStyle(.switch).labelsHidden().tint(appAccent) }
                settingRow("Animation speed", "How briskly the deck moves", divider: false) { Picker("", selection: $settings.animationSpeed) { Text("Fast").tag(AnimationSpeed.fast); Text("Normal").tag(AnimationSpeed.normal); Text("Slow").tag(AnimationSpeed.slow) }.pickerStyle(.segmented).frame(width: 195) }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Notes", "Choose how your notes look.")
            settingsSection("Writing") {
                settingRow("Handwriting", "The face your notes are written in") { Picker("", selection: $settings.fontName) { ForEach(noteFontNames, id: \.self) { Text($0).font(.custom($0, size: 14)) } }.frame(width: 160) }
                settingRow("Text size", "Body text in notes", divider: false) { Picker("", selection: $settings.textSize) { ForEach([10.0, 12.0, 14.0, 16.0, 18.0, 21.0, 24.0, 28.0], id: \.self) { Text("\(Int($0)) pt").tag($0) } }.frame(width: 90) }
            }
            settingsSection("New notes") {
                settingRow("Default note color", "Otherwise new notes rotate through every color", divider: false) {
                    HStack(spacing: 7) {
                        Toggle("Use one default color", isOn: $settings.useDefaultColor).toggleStyle(.switch).labelsHidden().tint(appAccent)
                        ForEach(NoteColor.allCases, id: \.rawValue) { colorButton($0) }
                    }
                }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Shortcuts", "Open Margin from anywhere.")
            settingsSection("Global shortcut") {
                settingRow("Shortcut", "Click the shortcut, then press a new key combination") { ShortcutRecorder(shortcut: $settings.quickShortcut).frame(width: 132, height: 28) }
                settingRow("Action", "Choose what opens from anywhere", divider: false) {
                    Picker("", selection: $settings.shortcutAction) { ForEach(ShortcutAction.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 155)
                }
            }
        }
    }

    private var cloud: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Cloud Sync", "Keep your notes on every Mac you use.")
            settingsSection("Sync") {
                settingRow("Sync my notes", "Use a folder in iCloud Drive or another syncing service", divider: settings.cloudSyncEnabled) {
                    Toggle("Sync my notes", isOn: Binding(
                        get: { settings.cloudSyncEnabled },
                        set: { cloudSync.setEnabled($0) }
                    )).toggleStyle(.switch).labelsHidden().tint(appAccent)
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
        VStack(alignment: .leading, spacing: 22) {
            heading("System", "Control how Margin behaves on your Mac.")
            settingsSection("Windows") {
                settingRow("Show in Dock", "Turn off to keep Margin in the menu bar only") { Toggle("Show in Dock", isOn: $settings.showInDock).toggleStyle(.switch).labelsHidden().tint(appAccent) }
                settingRow("Show over full-screen apps", "Keep the deck reachable in full screen") { Toggle("Show over full-screen apps", isOn: $settings.showOverFullScreen).toggleStyle(.switch).labelsHidden().tint(appAccent) }
                settingRow("Lock notes", "Hide note contents until you authenticate", divider: false) { Toggle("Lock notes", isOn: $settings.lockNotes).toggleStyle(.switch).labelsHidden().tint(appAccent) }
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Appearance", "Choose how Margin looks.")
            settingsSection("Interface") {
                settingRow("Theme", "Follow the Mac or choose a fixed appearance", divider: false) {
                    Picker("", selection: $settings.appearance) {
                        Text("Light").tag(AppearanceMode.light)
                        Text("System").tag(AppearanceMode.system)
                        Text("Dark").tag(AppearanceMode.dark)
                    }.pickerStyle(.segmented).frame(width: 210)
                }
            }
        }
    }

    private func colorButton(_ value: NoteColor) -> some View {
        Button { settings.defaultColor = value } label: {
            RoundedRectangle(cornerRadius: 6).fill(value.color).frame(width: 20, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(settings.defaultColor == value ? 0.65 : 0), lineWidth: 2.5).padding(-5))
                .frame(width: 25, height: 25)
        }.buttonStyle(HoverButtonStyle()).disabled(!settings.useDefaultColor).opacity(settings.useDefaultColor ? 1 : 0.38)
            .accessibilityLabel("\(value.name) default note color")
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("About", "Margin")
            settingsSection("Application") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Margin").font(.system(size: 15, weight: .semibold))
                            Text("Version \(versionText)").font(.system(size: 12)).foregroundStyle(.secondary)
                            Text("Sticky notes that live at the edge of your screen.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func heading(_ title: String, _ subtitle: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 29, weight: .medium, design: .serif)); Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) } }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            settingsCard(content: content)
        }
    }
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 18)
            .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.09)))
    }
    private func settingRow<Trailing: View>(_ title: String, _ subtitle: String, divider: Bool = true, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack { VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .medium)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); trailing() }.padding(.vertical, 14).overlay(alignment: .bottom) { Divider().opacity(divider ? 0.25 : 0) }
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
