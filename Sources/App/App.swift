import AppKit
import Carbon
import Combine
import LocalAuthentication
import QuartzCore
import ServiceManagement
import Sparkle
import SwiftUI

extension AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var isDark: Bool { (nsAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

private func hotKeyCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id.id)
    return noErr
}

final class HotKeyManager {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    init(bindings: [(GlobalShortcut, () -> Void)], reportError: (String) -> Void) {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(), hotKeyCallback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        for (index, binding) in bindings.enumerated() {
            let status = register(id: UInt32(index + 1), key: binding.0.keyCode, modifiers: binding.0.modifiers, action: binding.1)
            if status != noErr { reportError("Could not register \(binding.0.display). It may be in use by another app (error \(status)).") }
        }
    }

    deinit {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }

    private func register(id: UInt32, key: UInt32, modifiers: UInt32 = UInt32(cmdKey | optionKey), action: @escaping () -> Void) -> OSStatus {
        actions[id] = action
        var ref: EventHotKeyRef?
        let signature: OSType = 0x484D4E54 // HMNT
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
        return status
    }

    func fire(_ id: UInt32) { DispatchQueue.main.async { [weak self] in self?.actions[id]?() } }
}

final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performClose(_ sender: Any?) { onEscape?() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { onEscape?(); return }
        super.sendEvent(event)
    }
}

extension NSScreen {
    var displayID: String {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return String(number) }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

enum DeckPlacement {
    static func nearestSide(to point: NSPoint, in frame: NSRect) -> ScreenSide? {
        let distances: [(ScreenSide, CGFloat)] = [(.left, abs(point.x - frame.minX)), (.right, abs(point.x - frame.maxX)), (.bottom, abs(point.y - frame.minY))]
        guard frame.insetBy(dx: -1, dy: -1).contains(point),
              let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 48 else { return nil }
        return nearest.0
    }

    static func frame(screen: NSRect, visible: NSRect, side: ScreenSide, position: Double, count: Int, expanded: Bool) -> NSRect {
        let bottom = side == .bottom
        let expandedWidth = min(bottom ? max(280, CGFloat(count) * DeckCardMetrics.bottomStep + 160) : 480, visible.width)
        let expandedHeight = min(bottom ? 280 : DeckCardMetrics.stackHeight(count: count) + 120, visible.height)
        let width = expanded ? expandedWidth : (bottom ? max(38, CGFloat(count) * 22 + 20) : 12)
        let height = expanded ? expandedHeight : (bottom ? 12 : max(18, CGFloat(count) * 22 + 12))
        let fraction = min(1, max(0, position))
        // Use the same anchor when closed and open so the dots and notes never jump.
        let centerX = min(max(screen.minX + screen.width * fraction, visible.minX + expandedWidth / 2), visible.maxX - expandedWidth / 2)
        let centerY = min(max(screen.minY + screen.height * fraction, visible.minY + expandedHeight / 2), visible.maxY - expandedHeight / 2)
        return NSRect(x: bottom ? centerX - width / 2 : (side == .left ? screen.minX : screen.maxX - width),
                      y: bottom ? screen.minY : centerY - height / 2, width: width, height: height)
    }

    static func collectionBehavior(overFullScreen: Bool) -> NSWindow.CollectionBehavior {
        overFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenNone]
    }
}

final class EdgePanelModel: ObservableObject {
    @Published var expanded = false
    @Published var fanVisible = false
    @Published var noteLimit = 8
    var dragging = false
}

final class EdgePanelController: NSWindowController {
    static let expandedSize = NSSize(width: 480, height: 684)
    let screen: NSScreen
    let model = EdgePanelModel()
    private let settings: AppSettings
    private let store: NotesStore
    private var collapseWork: DispatchWorkItem?
    private var activationWork: DispatchWorkItem?
    private var notesObservation: AnyCancellable?
    private var hidden = false
    private var dockingPreview: NSPanel?
    private var animatePlacement = false

    init(screen: NSScreen, store: NotesStore, settings: AppSettings, coordinator: AppCoordinator) {
        self.screen = screen
        self.settings = settings
        self.store = store
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: EdgeDeckView(
            store: store, settings: settings, model: model,
            expand: { [weak self] value in self?.setExpanded(value) },
            hover: { [weak self] value in self?.setHovered(value) },
            beginDrag: { [weak self] in
                self?.model.dragging = true
                self?.activationWork?.cancel(); self?.collapseWork?.cancel()
            },
            draggingDeck: { [weak self] point in self?.previewDock(at: point) },
            endDrag: { [weak self] moved in
                guard let self, let frame = self.window?.frame else { return }
                self.dockingPreview?.orderOut(nil)
                self.model.dragging = false
                self.animatePlacement = moved
                guard moved else { self.refresh(); return }
                coordinator.dockDeck(at: NSEvent.mouseLocation, center: NSPoint(x: frame.midX, y: frame.midY))
            },
            create: { coordinator.createNote(on: screen) },
            open: { coordinator.openEditor($0, on: screen) },
            showAll: { coordinator.showAllNotes() },
            showArchive: { coordinator.showArchive() },
            showSettings: { coordinator.showSettings() }
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        refresh()
        notesObservation = store.$notes.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func close() {
        activationWork?.cancel(); collapseWork?.cancel()
        dockingPreview?.close()
        super.close()
    }

    private func previewDock(at point: NSPoint) {
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let side = DeckPlacement.nearestSide(to: point, in: target.frame) else {
            dockingPreview?.orderOut(nil)
            return
        }
        if dockingPreview == nil {
            let preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            preview.isOpaque = false; preview.backgroundColor = .clear
            preview.hasShadow = false; preview.ignoresMouseEvents = true
            preview.level = .floating; preview.isReleasedWhenClosed = false
            preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let label = NSTextField(labelWithString: "")
            label.alignment = .center; label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = MarginPalette.accent
            label.wantsLayer = true
            label.layer?.backgroundColor = MarginPalette.accent.withAlphaComponent(0.16).cgColor
            label.layer?.borderColor = MarginPalette.accent.withAlphaComponent(0.7).cgColor
            label.layer?.borderWidth = 2; label.layer?.cornerRadius = 12
            preview.contentView = label
            dockingPreview = preview
        }
        guard let preview = dockingPreview else { return }
        let position = side == settings.side && window != nil
            ? (side == .bottom ? window!.frame.midX : window!.frame.midY)
            : (side == .bottom ? point.x : point.y)
        let fraction = side == .bottom ? (position - target.frame.minX) / target.frame.width
            : (position - target.frame.minY) / target.frame.height
        var frame = DeckPlacement.frame(screen: target.frame, visible: target.visibleFrame, side: side,
                                        position: fraction, count: min(store.active.count, model.noteLimit), expanded: true)
        if side != .bottom {
            frame.size.width = DeckCardMetrics.visibleWidth
            frame.origin.x = side == .left ? target.frame.minX : target.frame.maxX - frame.width
        }
        (preview.contentView as? NSTextField)?.stringValue = side == .left ? "← Release to dock left" : side == .right ? "Release to dock right →" : "↓ Release to dock below"
        let appearing = !preview.isVisible
        if appearing { preview.setFrame(frame, display: true); preview.alphaValue = 0; preview.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            preview.animator().alphaValue = 1
            preview.animator().setFrame(frame, display: true)
        }
    }

    func setHidden(_ value: Bool) {
        hidden = value
        if value {
            activationWork?.cancel(); activationWork = nil; collapseWork?.cancel()
            window?.orderOut(nil)
        } else { refresh() }
    }

    func refresh() {
        guard !model.dragging else { return }
        activationWork?.cancel(); activationWork = nil
        window?.collectionBehavior = DeckPlacement.collectionBehavior(overFullScreen: settings.showOverFullScreen).union([.stationary, .ignoresCycle])
        model.noteLimit = settings.side == .bottom
            ? min(8, max(1, Int((screen.visibleFrame.width - 160) / DeckCardMetrics.bottomStep)))
            : min(8, max(1, Int((screen.visibleFrame.height - 120 - DeckCardMetrics.height) / DeckCardMetrics.step) + 1))
        resize(expanded: settings.keepOpen || model.expanded)
        model.fanVisible = model.expanded
    }

    func setHovered(_ inside: Bool) {
        guard !model.dragging, !hidden else { return }
        if !inside { activationWork?.cancel(); activationWork = nil; setExpanded(false); return }
        collapseWork?.cancel()
        if model.expanded { model.fanVisible = true; return }
        guard activationWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.activationWork = nil
            self?.setExpanded(true)
        }
        activationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.activationDelay, execute: work)
    }

    func setExpanded(_ value: Bool) {
        guard !model.dragging, !hidden else { return }
        collapseWork?.cancel()
        if value {
            activationWork?.cancel(); activationWork = nil
            if !model.expanded { resize(expanded: true) }
            DispatchQueue.main.async { [weak self] in self?.model.fanVisible = true }
            return
        }
        if settings.keepOpen { model.fanVisible = true; return }
        model.fanVisible = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window,
                  Self.shouldCollapse(pointer: NSEvent.mouseLocation, in: window.frame) else { return }
            resize(expanded: false)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.fanDuration, execute: work)
    }

    func collapseImmediately() {
        activationWork?.cancel(); activationWork = nil
        collapseWork?.cancel()
        guard !settings.keepOpen else { return }
        model.fanVisible = false
        resize(expanded: false)
    }

    static func shouldCollapse(pointer: NSPoint, in frame: NSRect) -> Bool { !frame.contains(pointer) }

    private func resize(expanded: Bool) {
        guard let window else { return }
        model.expanded = expanded
        if !expanded { model.fanVisible = false }
        let frame = DeckPlacement.frame(screen: screen.frame, visible: screen.visibleFrame, side: settings.side,
                                        position: settings.deckPosition, count: min(store.active.count, model.noteLimit), expanded: expanded)
        if animatePlacement && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(frame, display: true)
            }
        } else { window.setFrame(frame, display: true) }
        animatePlacement = false
        if hidden { window.orderOut(nil) } else { window.orderFrontRegardless() }
    }
}

final class StickyWindowController: NSWindowController, NSWindowDelegate {
    let noteID: UUID
    private let store: NotesStore
    private let settings: AppSettings
    private var deckFrame = NSRect.zero
    private var isDismissing = false
    private var remembersMoves = false
    private var escapeMonitor: Any?

    static func shouldRememberMove(hasFinishedOpening: Bool, isDismissing: Bool) -> Bool {
        hasFinishedOpening && !isDismissing
    }

    init(note: Note, screen: NSScreen, store: NotesStore, settings: AppSettings, coordinator: AppCoordinator) {
        noteID = note.id
        self.store = store
        self.settings = settings
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.onEscape = { [weak self] in self?.requestDismiss() }
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !settings.appearance.isDark
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = DeckPlacement.collectionBehavior(overFullScreen: settings.showOverFullScreen)
        panel.contentView = NSHostingView(rootView: NoteEditorView(
            noteID: note.id, store: store, settings: settings,
            close: { [weak self] in self?.requestDismiss() },
            archive: { [weak self] in store.archive(note.id); self?.dismiss() },
            delete: { [weak self] in store.delete(note.id); self?.dismiss() },
            pin: { [weak self] pinned in self?.setPinned(pinned) }
        ))
        let size = NSSize(width: 448, height: 424)
        let proposedOrigin: NSPoint
        if note.pinned, let x = note.pinX, let y = note.pinY { proposedOrigin = NSPoint(x: x, y: y) }
        else if let position = settings.lastNotePosition { proposedOrigin = NSPoint(x: position.x, y: position.y) }
        else {
            switch settings.side {
            case .right: proposedOrigin = NSPoint(x: screen.visibleFrame.maxX - size.width - 28, y: screen.visibleFrame.midY - size.height / 2)
            case .left: proposedOrigin = NSPoint(x: screen.visibleFrame.minX + 28, y: screen.visibleFrame.midY - size.height / 2)
            case .bottom: proposedOrigin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 28)
            }
        }
        let targetOrigin = NSPoint(
            x: min(max(proposedOrigin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width),
            y: min(max(proposedOrigin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - size.height)
        )
        let targetFrame = NSRect(origin: targetOrigin, size: size)
        let active = store.active
        let anchorFrame = DeckPlacement.frame(screen: screen.frame, visible: screen.visibleFrame, side: settings.side,
                                               position: settings.deckPosition, count: min(active.count, 8), expanded: false)
        let index = active.firstIndex(where: { $0.id == note.id }) ?? max(0, active.count - 1)
        let slotOffset = (CGFloat(index) - CGFloat(max(0, min(active.count, 8) - 1)) / 2) * (settings.side == .bottom ? DeckCardMetrics.bottomStep : DeckCardMetrics.step)
        if settings.side == .bottom {
            deckFrame = NSRect(
                x: anchorFrame.midX + slotOffset - DeckCardMetrics.visibleWidth / 2,
                y: screen.frame.minY,
                width: DeckCardMetrics.visibleWidth,
                height: DeckCardMetrics.height
            )
        } else {
            deckFrame = NSRect(
                x: settings.side == .right ? screen.visibleFrame.maxX - DeckCardMetrics.width : screen.visibleFrame.minX,
                y: anchorFrame.midY - slotOffset - DeckCardMetrics.height / 2,
                width: DeckCardMetrics.width,
                height: DeckCardMetrics.height
            )
        }
        let morph = !note.pinned && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(morph ? deckFrame : targetFrame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isKeyWindow == true else { return event }
            self?.requestDismiss()
            return nil
        }
        guard morph else { panel.contentMinSize = NSSize(width: 420, height: 300); remembersMoves = true; return }
        DispatchQueue.main.async { [weak self] in
            self?.animate(to: targetFrame) {
                panel.contentMinSize = NSSize(width: 420, height: 300)
                self?.remembersMoves = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    func refreshCollectionBehavior() {
        window?.collectionBehavior = DeckPlacement.collectionBehavior(overFullScreen: settings.showOverFullScreen)
        window?.hasShadow = !settings.appearance.isDark
    }

    private func animate(to frame: NSRect, completion: (() -> Void)? = nil) {
        guard let panel = window else { completion?(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settings.cardDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 1.05, 0.30, 1.00)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { completion?() }
    }

    private func requestDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        window?.endEditing(for: nil)
        DispatchQueue.main.async { [weak self] in self?.finishDismiss() }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        finishDismiss()
    }

    private func finishDismiss() {
        store.flush(noteID)
        guard store.note(noteID)?.pinned != true,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { close(); return }
        guard let panel = window else { close(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settings.cardDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 1.05, 0.30, 1.00)
            panel.animator().setFrame(deckFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in self?.close() }
    }

    private func setPinned(_ pinned: Bool) {
        guard var note = store.note(noteID), let frame = window?.frame else { return }
        note.pinned = pinned
        if pinned { note.pinX = frame.origin.x; note.pinY = frame.origin.y }
        settings.rememberNotePosition(x: frame.origin.x, y: frame.origin.y)
        store.update(note, immediate: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard Self.shouldRememberMove(hasFinishedOpening: remembersMoves, isDismissing: isDismissing),
              let frame = window?.frame else { return }
        settings.rememberNotePosition(x: frame.origin.x, y: frame.origin.y)
        guard var note = store.note(noteID), note.pinned else { return }
        note.pinX = frame.origin.x; note.pinY = frame.origin.y
        store.update(note)
    }
}

final class AppCoordinator {
    let store: NotesStore
    let settings: AppSettings
    let cloudSync: CloudSyncController
    let updater: SPUUpdater
    private var edges: [ObjectIdentifier: EdgePanelController] = [:]
    private var editors: [UUID: StickyWindowController] = [:]
    private var allNotes: NSWindowController?
    private var archiveWindow: NSWindowController?
    private var settingsWindow: NSWindowController?
    private var onboarding: NSWindowController?
    private var deckHidden = false

    init(store: NotesStore, settings: AppSettings, cloudSync: CloudSyncController, updater: SPUUpdater) {
        self.store = store; self.settings = settings; self.cloudSync = cloudSync; self.updater = updater
        settings.onChange = { [weak self] in DispatchQueue.main.async {
            guard let self else { return }
            NSApp.appearance = self.settings.appearance.nsAppearance
            self.refreshPanels()
        } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildPanels() }
    }

    func start() {
        // Cloud Sync is intentionally unavailable in this build.
        rebuildPanels()
        if CommandLine.arguments.contains("--ui-test") {
            if CommandLine.arguments.contains("--settings-test") { showSettings(); return }
            if CommandLine.arguments.contains("--capsule-test") { return }
            showDeck()
            if CommandLine.arguments.contains("--deck-test") { return }
            showAllNotes()
            if CommandLine.arguments.contains("--editor-test"), let note = store.active.first { openEditor(note.id) }
            return
        }
        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") { showOnboarding() }
        else { restoreEditors() }
    }

    func rebuildPanels() {
        edges.values.forEach { $0.close() }; edges.removeAll()
        for screen in targetScreens {
            let controller = EdgePanelController(screen: screen, store: store, settings: settings, coordinator: self)
            edges[ObjectIdentifier(screen)] = controller
            controller.setHidden(deckHidden)
        }
    }

    private var targetScreens: [NSScreen] {
        Self.targetScreens(from: NSScreen.screens, main: NSScreen.screens.first, selection: settings.display, id: { $0.displayID })
    }

    func refreshPanels() {
        let targetIDs = Set(targetScreens.map(ObjectIdentifier.init))
        if Set(edges.keys) != targetIDs { rebuildPanels() }
        else { edges.values.forEach { $0.refresh() } }
        editors.values.forEach { $0.refreshCollectionBehavior() }
    }

    static func targetScreens<Screen>(from screens: [Screen], main: Screen?, selection: String, id: (Screen) -> String) -> [Screen] {
        if selection == "all" { return screens }
        if selection != "main", let selected = screens.first(where: { id($0) == selection }) { return [selected] }
        return main.map { [$0] } ?? Array(screens.prefix(1))
    }

    func showDeck() {
        setDeckHidden(false)
        edges.values.forEach { $0.setExpanded(true) }
    }

    func toggleDeckHidden() { setDeckHidden(!deckHidden) }

    private func setDeckHidden(_ hidden: Bool) {
        guard deckHidden != hidden else { return }
        store.flushAll()
        deckHidden = hidden
        edges.values.forEach { $0.setHidden(hidden) }
        editors.values.forEach { if hidden { $0.window?.orderOut(nil) } else { $0.window?.orderFrontRegardless() } }
    }

    func cycleDeckPosition() {
        let sides = ScreenSide.allCases
        settings.side = sides[(sides.firstIndex(of: settings.side)! + 1) % sides.count]
        settings.deckPosition = 0.5
        showDeck()
    }

    func dockDeck(at point: NSPoint, center: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let side = DeckPlacement.nearestSide(to: point, in: screen.frame) else {
            // No preferences change on a rejected drop; refresh restores the saved anchor.
            refreshPanels()
            return
        }
        let anchor = side == settings.side ? center : point
        settings.deckPosition = min(1, max(0, side == .bottom
            ? (anchor.x - screen.frame.minX) / screen.frame.width
            : (anchor.y - screen.frame.minY) / screen.frame.height))
        settings.side = side
        if settings.display != "all" { settings.display = screen.displayID }
        refreshPanels()
    }

    func performQuickAction() {
        if settings.shortcutAction == .newNote { createNote(); return }
        if let note = store.active.first { openEditor(note.id) } else { createNote() }
    }

    func createNote(on screen: NSScreen? = nil) {
        let note = store.create()
        openEditor(note.id, on: screen ?? NSScreen.main)
    }

    func openEditor(_ id: UUID, on screen: NSScreen? = nil) {
        setDeckHidden(false)
        guard let note = store.note(id) else { return }
        var savedPoint: NSPoint?
        if note.pinned, let x = note.pinX, let y = note.pinY { savedPoint = NSPoint(x: x, y: y) }
        else if let position = settings.lastNotePosition { savedPoint = NSPoint(x: position.x, y: position.y) }
        guard let targetScreen = screen ?? savedPoint.flatMap({ point in NSScreen.screens.first { $0.visibleFrame.contains(point) } }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        edges[ObjectIdentifier(targetScreen)]?.collapseImmediately()
        if let current = editors[id] { settings.lastOpenNoteID = id; current.window?.makeKeyAndOrderFront(nil); return }
        let show = { [weak self] in
            guard let self else { return }
            settings.lastOpenNoteID = id
            let controller = StickyWindowController(note: note, screen: targetScreen, store: store, settings: settings, coordinator: self)
            editors[id] = controller
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window, queue: .main) { [weak self] _ in self?.editors[id] = nil }
        }
        guard settings.lockNotes else { show(); return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your notes") { success, _ in
            if success { DispatchQueue.main.async(execute: show) }
        }
    }

    func showAllNotes(filter: NoteFilter = .all) {
        if let allNotes { allNotes.window?.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 786, height: 634), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "All Notes"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: AllNotesView(store: store, initialFilter: filter, open: { [weak self] in self?.openEditor($0) }))
        let controller = NSWindowController(window: window); allNotes = controller
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.allNotes = nil }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func showArchive() {
        if let archiveWindow { archiveWindow.window?.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 796, height: 494), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Archive"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: ArchiveView(store: store, open: { [weak self] in self?.openEditor($0) }))
        let controller = NSWindowController(window: window); archiveWindow = controller
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.archiveWindow = nil }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if let settingsWindow { settingsWindow.window?.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 600), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 780, height: 480)
        window.title = "Settings"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, cloudSync: cloudSync, updater: updater))
        let controller = NSWindowController(window: window); settingsWindow = controller
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.settingsWindow = nil }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 468), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: OnboardingView { [weak self] addLoginItem in
            if addLoginItem { try? SMAppService.mainApp.register() }
            UserDefaults.standard.set(true, forKey: "onboardingCompleted")
            guard let self else { return }
            let note = store.seedWelcomeIfNeeded()
            onboarding?.close(); onboarding = nil
            openEditor(note.id)
        })
        let controller = NSWindowController(window: window); onboarding = controller
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreEditors() {
        let lastOpen = settings.lastOpenNoteID
        for note in store.active where note.pinned { openEditor(note.id) }
        if let id = lastOpen, store.active.contains(where: { $0.id == id }) { openEditor(id) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    struct EditCommand {
        let title: String
        let action: Selector
        let key: String
        var modifiers: NSEvent.ModifierFlags = .command
    }
    static let editCommands = [
        EditCommand(title: "Undo", action: Selector(("undo:")), key: "z"),
        EditCommand(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
        EditCommand(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"),
        EditCommand(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"),
        EditCommand(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"),
        EditCommand(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a")
    ]
    let settings = AppSettings(defaults: CommandLine.arguments.contains("--ui-test")
        ? UserDefaults(suiteName: "margin-ui-test-\(ProcessInfo.processInfo.processIdentifier)")! : .standard)
    lazy var store = NotesStore(settings: settings)
    lazy var cloudSync = CloudSyncController(store: store, settings: settings)
    private let updaterController = SPUStandardUpdaterController(startingUpdater: !CommandLine.arguments.contains("--ui-test"), updaterDelegate: nil, userDriverDelegate: nil)
    lazy var coordinator = AppCoordinator(store: store, settings: settings, cloudSync: cloudSync, updater: updaterController.updater)
    private var hotKeys: HotKeyManager?
    private var shortcutObservation: AnyCancellable?
    private var recordingObservation: AnyCancellable?
    private var shortcutRecording = false
    private var dockObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var leftSideItem: NSMenuItem?
    private var rightSideItem: NSMenuItem?
    private var bottomSideItem: NSMenuItem?

    static func makeMainMenu(settings: AppSettings? = nil, target: AnyObject? = nil) -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let settingsShortcut = settings?.shortcut(for: .settings) ?? KeyboardAction.settings.standard
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(statusSettings(_:)), keyEquivalent: settingsShortcut.menuKey)
        settingsItem.keyEquivalentModifierMask = settingsShortcut.eventModifiers
        settingsItem.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let closeShortcut = settings?.shortcut(for: .close) ?? KeyboardAction.close.standard
        let closeItem = fileMenu.addItem(withTitle: "Close", action: #selector(statusCloseWindow(_:)), keyEquivalent: closeShortcut.menuKey)
        closeItem.target = target
        closeItem.keyEquivalentModifierMask = closeShortcut.eventModifiers
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for command in editCommands {
            if command.title == "Cut" { editMenu.addItem(.separator()) }
            let item = editMenu.addItem(withTitle: command.title, action: command.action, keyEquivalent: command.key)
            item.keyEquivalentModifierMask = command.modifiers
        }
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Start Dictation…", action: Selector(("startDictation:")), keyEquivalent: "")
        editMenu.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")
        editItem.submenu = editMenu
        return mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = settings.appearance.nsAppearance
        NSApp.setActivationPolicy(Self.activationPolicy(showInDock: settings.showInDock, uiTest: CommandLine.arguments.contains("--ui-test")))
        NSApp.mainMenu = Self.makeMainMenu(settings: settings, target: self)
        if !CommandLine.arguments.contains("--ui-test") { installHotKeys() }
        shortcutObservation = settings.$shortcuts.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.installHotKeys()
                NSApp.mainMenu = Self.makeMainMenu(settings: self.settings, target: self)
            }
        }
        dockObservation = settings.$showInDock.dropFirst().sink { show in NSApp.setActivationPolicy(show ? .regular : .accessory) }
        recordingObservation = NotificationCenter.default.publisher(for: .marginShortcutRecording).sink { [weak self] event in
            guard let self else { return }
            self.shortcutRecording = event.object as? Bool ?? false
            if self.shortcutRecording { self.hotKeys = nil } else { self.installHotKeys() }
        }
        installStatusItem()
        coordinator.start()
    }

    static func activationPolicy(showInDock: Bool, uiTest: Bool) -> NSApplication.ActivationPolicy { showInDock || uiTest ? .regular : .accessory }

    private func installHotKeys() {
        guard !shortcutRecording else { return }
        hotKeys = nil // Release old registrations before installing replacements.
        settings.shortcutError = nil
        let bindings: [(GlobalShortcut, () -> Void)] = KeyboardAction.allCases.filter(\.isGlobal).map { action in
            (settings.shortcut(for: action), { [weak self] in
                guard let self else { return }
                switch action {
                case .quick: self.coordinator.performQuickAction()
                case .allNotes: self.coordinator.showAllNotes()
                case .archive: self.coordinator.showArchive()
                case .position: self.coordinator.cycleDeckPosition()
                case .hide: self.coordinator.toggleDeckHidden()
                case .settings, .close: break
                }
            })
        }
        hotKeys = HotKeyManager(bindings: bindings, reportError: { settings.shortcutError = $0 })
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Margin")
        item.button?.toolTip = "Margin"
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(statusNewNote(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "All Notes…", action: #selector(statusAllNotes(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Archive…", action: #selector(statusArchive(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(statusSettings(_:)), keyEquivalent: "")
        let screenSide = NSMenuItem(title: "Screen Side", action: nil, keyEquivalent: "")
        screenSide.image = NSImage(systemSymbolName: "rectangle.lefthalf.inset.filled", accessibilityDescription: nil)
        let screenSideMenu = NSMenu()
        leftSideItem = screenSideMenu.addItem(withTitle: "Left", action: #selector(statusSideLeft(_:)), keyEquivalent: "")
        rightSideItem = screenSideMenu.addItem(withTitle: "Right", action: #selector(statusSideRight(_:)), keyEquivalent: "")
        bottomSideItem = screenSideMenu.addItem(withTitle: "Bottom", action: #selector(statusSideBottom(_:)), keyEquivalent: "")
        screenSide.submenu = screenSideMenu
        menu.addItem(screenSide)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Margin Deck", action: #selector(statusShowDeck(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Hide / Show Deck and Notes", action: #selector(statusToggleDeck(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(statusCheckForUpdates(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        item.menu = menu; statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        leftSideItem?.state = settings.side == .left ? .on : .off
        rightSideItem?.state = settings.side == .right ? .on : .off
        bottomSideItem?.state = settings.side == .bottom ? .on : .off
    }

    @objc private func statusNewNote(_ sender: Any?) { coordinator.createNote() }
    @objc private func statusAllNotes(_ sender: Any?) { coordinator.showAllNotes() }
    @objc private func statusArchive(_ sender: Any?) { coordinator.showArchive() }
    @objc private func statusSettings(_ sender: Any?) { coordinator.showSettings() }
    @objc fileprivate func statusCloseWindow(_ sender: Any?) { (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(sender) }
    @objc private func statusToggleDeck(_ sender: Any?) { coordinator.toggleDeckHidden() }
    @objc private func statusShowDeck(_ sender: Any?) { coordinator.showDeck() }
    @objc private func statusCheckForUpdates(_ sender: Any?) { updaterController.checkForUpdates(sender) }
    @objc private func statusSideLeft(_ sender: Any?) { settings.side = .left }
    @objc private func statusSideRight(_ sender: Any?) { settings.side = .right }
    @objc private func statusSideBottom(_ sender: Any?) { settings.side = .bottom }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum AppSelfCheck {
    static func run() throws {
        let hasSelectAll = AppDelegate.editCommands.contains { $0.key == "a" && $0.action == #selector(NSText.selectAll(_:)) }
        guard hasSelectAll else { throw SelfCheckFailure("Command-A is not routed to Select All") }
        if NSApp != nil {
            let hasClose = AppDelegate.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items).contains {
                $0.keyEquivalent == "w" && $0.action == #selector(AppDelegate.statusCloseWindow(_:))
            }
            guard hasClose else { throw SelfCheckFailure("Command-W is not routed to Close") }
        }
        guard GlobalShortcut.standard.display == "⌥⌘N", ScreenSide.allCases.contains(.bottom) else {
            throw SelfCheckFailure("Shortcut display or bottom docking is not configured")
        }
        guard AppDelegate.activationPolicy(showInDock: false, uiTest: false) == .accessory,
              AppDelegate.activationPolicy(showInDock: true, uiTest: false) == .regular else {
            throw SelfCheckFailure("Dock visibility does not map to the app activation policy")
        }
        guard AppCoordinator.targetScreens(from: [1, 2], main: 1, selection: "all", id: String.init) == [1, 2],
              AppCoordinator.targetScreens(from: [1, 2], main: 1, selection: "main", id: String.init) == [1],
              AppCoordinator.targetScreens(from: [1, 2], main: 1, selection: "2", id: String.init) == [2],
              AppCoordinator.targetScreens(from: [1, 2], main: 1, selection: "disconnected", id: String.init) == [1] else {
            throw SelfCheckFailure("Display scope does not select all screens or only the main screen")
        }
        guard StickyWindowController.shouldRememberMove(hasFinishedOpening: true, isDismissing: false),
              !StickyWindowController.shouldRememberMove(hasFinishedOpening: true, isDismissing: true) else {
            throw SelfCheckFailure("Closing a note overwrites its remembered window position")
        }
        guard Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else {
            throw SelfCheckFailure("Signed automatic updates are not configured")
        }
        guard ChecklistNSTextView.links(in: "Visit https://example.com now").first?.0.absoluteString == "https://example.com" else {
            throw SelfCheckFailure("URLs are not recognized in note text")
        }
        guard ChecklistNSTextView.opensLink(with: []),
              !ChecklistNSTextView.opensLink(with: [.command]),
              !ChecklistNSTextView.opensLink(with: [.option]),
              !ChecklistNSTextView.opensLink(with: [.control]),
              !ChecklistNSTextView.opensLink(with: [.shift]),
              !ChecklistNSTextView.opensLink(with: [], keyHeld: true),
              ChecklistNSTextView.opensLink(with: [.capsLock]) else {
            throw SelfCheckFailure("Modified clicks do not place the caret inside links")
        }
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: -1440, y: 40, width: 1440, height: 836)
        for side in ScreenSide.allCases {
            for count in [1, 8] {
                let closed = DeckPlacement.frame(screen: screen, visible: visible, side: side, position: 0.5, count: count, expanded: false)
                let open = DeckPlacement.frame(screen: screen, visible: visible, side: side, position: 0.5, count: count, expanded: true)
                guard side == .bottom ? (closed.midX == screen.midX && open.midX == closed.midX) : (closed.midY == screen.midY && open.midY == closed.midY) else {
                    throw SelfCheckFailure("Dots and notes are not centered on the same screen-edge anchor")
                }
                for position in [0.0, 1.0] {
                    let moved = DeckPlacement.frame(screen: screen, visible: visible, side: side, position: position, count: count, expanded: true)
                    guard screen.contains(moved) else { throw SelfCheckFailure("Dragging can strand the deck offscreen") }
                }
            }
        }
        guard DeckPlacement.nearestSide(to: NSPoint(x: -1430, y: 450), in: screen) == .left,
              DeckPlacement.nearestSide(to: NSPoint(x: -10, y: 450), in: screen) == .right,
              DeckPlacement.nearestSide(to: NSPoint(x: -720, y: 5), in: screen) == .bottom,
              DeckPlacement.nearestSide(to: NSPoint(x: screen.midX, y: screen.midY), in: screen) == nil,
              DeckPlacement.nearestSide(to: NSPoint(x: screen.midX, y: screen.maxY - 5), in: screen) == nil,
              DeckPlacement.nearestSide(to: NSPoint(x: screen.minX + 49, y: screen.midY), in: screen) == nil,
              DeckPlacement.nearestSide(to: NSPoint(x: screen.minX + 48, y: screen.midY), in: screen) == .left,
              DeckPlacement.nearestSide(to: NSPoint(x: screen.maxX + 100, y: screen.midY), in: screen) == nil,
              DeckPlacement.collectionBehavior(overFullScreen: false).contains(.fullScreenNone),
              !DeckPlacement.collectionBehavior(overFullScreen: false).contains(.fullScreenAuxiliary),
              DeckPlacement.collectionBehavior(overFullScreen: true).contains(.fullScreenAuxiliary),
              DeckCardMetrics.liftedOffset == 34 else {
            throw SelfCheckFailure("Deck docking, full-screen exclusion or preview visibility is incorrect")
        }
        guard KeyboardAction.allCases.map({ $0.standard.display }) == ["⌥⌘N", "⌥⌘L", "⌥⌘A", "⌥⌘E", "⌃⌥⌘H", "⌘,", "⌘W"] else {
            throw SelfCheckFailure("Default keyboard shortcuts do not match the requested actions")
        }
        let deckFrame = NSRect(origin: NSPoint(x: 100, y: 100), size: EdgePanelController.expandedSize)
        guard !EdgePanelController.shouldCollapse(pointer: NSPoint(x: 579, y: 210), in: deckFrame) else {
            throw SelfCheckFailure("Deck collapses while the cursor is still inside it")
        }
        guard EdgePanelController.shouldCollapse(pointer: NSPoint(x: 10, y: 10), in: deckFrame) else {
            throw SelfCheckFailure("Deck stays open after the cursor leaves it")
        }
        guard let checklist = ChecklistLine.parse("- [x] ~~shipped~~"), checklist.checked, checklist.text == "shipped", ChecklistLine.parse("plain text") == nil else {
            throw SelfCheckFailure("Checklist preview parsing failed")
        }
        guard ChecklistLine.toggled("- [ ] shipped") == "- [x] ~~shipped~~",
              ChecklistLine.toggled("- [x] ~~shipped~~") == "- [ ] shipped" else {
            throw SelfCheckFailure("Checklist completion does not preserve the stored syntax")
        }
        let checkmark = ChecklistMarkGeometry.points(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        guard checkmark.middle.y > checkmark.start.y, checkmark.end.y < checkmark.middle.y else {
            throw SelfCheckFailure("Completed checklist items draw an inverted checkmark")
        }
        guard SettingsView.visibleVersion(shortVersion: "1.0.2") == "1.0.2" else {
            throw SelfCheckFailure("The About screen exposes the internal build number")
        }
        guard contrastRatio(MarginPalette.accent(isDark: true), MarginPalette.accentForeground(isDark: true)) >= 4.5,
              contrastRatio(MarginPalette.accent(isDark: true), MarginPalette.selectionSurface(isDark: true)) >= 4.5,
              contrastRatio(MarginPalette.selectionBorder(isDark: true), MarginPalette.selectionSurface(isDark: true)) >= 3,
              contrastRatio(MarginPalette.accent(isDark: false), MarginPalette.accentForeground(isDark: false)) >= 4.5,
              contrastRatio(MarginPalette.accent(isDark: false), MarginPalette.selectionSurface(isDark: false)) >= 4.5,
              contrastRatio(MarginPalette.selectionBorder(isDark: false), MarginPalette.selectionSurface(isDark: false)) >= 3 else {
            throw SelfCheckFailure("Selected controls do not have enough contrast")
        }
        guard !DeckHoverGate.isReady(now: 1, readyAt: 2), DeckHoverGate.isReady(now: 2, readyAt: 2) else {
            throw SelfCheckFailure("Deck hover activates before the fan settles")
        }
        guard DeckHoverGate.opensOnTap(mode: .hover, alreadyPreviewed: false),
              !DeckHoverGate.opensOnTap(mode: .click, alreadyPreviewed: false),
              DeckHoverGate.opensOnTap(mode: .click, alreadyPreviewed: true) else {
            throw SelfCheckFailure("Deck hover/click activation modes are wired incorrectly")
        }
        guard DeckCardMetrics.hoverWidth(lifted: false, index: 0) == 34,
              DeckCardMetrics.hoverWidth(lifted: false, index: 3) == 46,
              DeckCardMetrics.hoverWidth(lifted: true, index: 0) == 182,
              DeckCardMetrics.hoverHeight(lifted: false, isLast: false) == 68,
              DeckCardMetrics.hoverHeight(lifted: false, isLast: true) == 152,
              DeckCardMetrics.spreadOffset(index: 0, hoveredIndex: 0) == 0,
              DeckCardMetrics.spreadOffset(index: 1, hoveredIndex: 0) == 24,
              DeckCardMetrics.spreadOffset(index: 1, hoveredIndex: nil) == 0 else {
            throw SelfCheckFailure("Deck hover targets do not match the stationary note slots")
        }
        guard NSApp != nil else { return }
        let markdownEditor = ChecklistNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        markdownEditor.noteFont = .systemFont(ofSize: 16)
        let markdown = "# Heading\n## Smaller\n### Smallest\n\n**Bold** and *italic* with ~~strike~~ and `code`\n[Link](https://example.com)\n\n```\n- [ ] literal code\n```\n- [ ] real task"
        markdownEditor.string = markdown
        markdownEditor.applyStyle()
        func attributes(_ text: String) -> [NSAttributedString.Key: Any] {
            markdownEditor.textStorage!.attributes(at: (markdown as NSString).range(of: text).location, effectiveRange: nil)
        }
        guard markdownEditor.string == markdown,
              (attributes("##")[.foregroundColor] as? NSColor)?.alphaComponent == 0,
              (attributes("**")[.font] as? NSFont)?.pointSize == 0.01,
              (attributes("https://example.com")[.foregroundColor] as? NSColor)?.alphaComponent == 0,
              (attributes("- [ ] literal")[.foregroundColor] as? NSColor)?.alphaComponent != 0,
              (attributes("Heading")[.font] as? NSFont)?.pointSize == 26.4,
              (attributes("Smaller")[.font] as? NSFont)?.pointSize == 22.4,
              NSFontManager.shared.traits(of: attributes("Bold")[.font] as! NSFont).contains(.boldFontMask),
              NSFontManager.shared.traits(of: attributes("italic")[.font] as! NSFont).contains(.italicFontMask),
              attributes("strike")[.strikethroughStyle] != nil,
              attributes("code")[.backgroundColor] != nil,
              (attributes("Link")[.link] as? URL)?.absoluteString == "https://example.com",
              markdownEditor.checkboxRect(at: (markdown as NSString).range(of: "- [ ] literal").location) == nil,
              markdownEditor.checkboxRect(at: (markdown as NSString).range(of: "- [ ] real").location) != nil else {
            throw SelfCheckFailure("Markdown formatting changes the source, misses styles, or turns code into a task")
        }
        markdownEditor.markdownEnabled = false; markdownEditor.applyStyle()
        guard (attributes("Heading")[.font] as? NSFont)?.pointSize == 16 else {
            throw SelfCheckFailure("Markdown formatting cannot be turned off")
        }
        markdownEditor.markdownEnabled = true
        markdownEditor.string = "## Test\n- [ ] Aligned task\n[Website](https://example.com)"
        markdownEditor.applyStyle()
        let website = (markdownEditor.string as NSString).range(of: "Website")
        guard (markdownEditor.textStorage?.attribute(.link, at: website.location, effectiveRange: nil) as? URL)?.host == "example.com",
              (markdownEditor.textStorage?.attribute(.font, at: website.location, effectiveRange: nil) as? NSFont)?.pointSize == 16 else {
            throw SelfCheckFailure("Markdown links after checklist continuations lose their label")
        }
        let exported = NoteFile(note: Note(title: "../My: note/✓", body: markdown))
        let exportedURL = try exported.write()
        defer { try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent()) }
        guard exportedURL.lastPathComponent == exported.filename, exported.filename.hasSuffix(".md"),
              !exported.filename.contains("/"), !exported.filename.hasPrefix("."),
              try String(contentsOf: exportedURL, encoding: .utf8) == CloudSyncEngine.renderMarkdown(exported.note),
              NoteFile(note: Note(title: "")).filename == "Untitled_note.md",
              NoteFile(note: Note(title: "file_name.md.md")).filename == "file_name.md",
              try NoteFile(note: Note(title: "file_name.md")).itemProvider().suggestedName == "file_name" else {
            throw SelfCheckFailure("Markdown export loses content or creates an unsafe filename")
        }
        let dragWindow = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        dragWindow.isReleasedWhenClosed = false
        defer { dragWindow.close() }
        let dragHandle = DragHandleNSView(frame: NSRect(x: 0, y: 0, width: 32, height: 16))
        dragWindow.contentView = dragHandle
        var began = false
        var completed: [Bool] = []
        dragHandle.willDrag = { began = true }
        dragHandle.didDrag = { completed.append($0) }
        func dragEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: dragWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let startFrame = dragWindow.frame
        dragHandle.mouseDown(with: dragEvent(.leftMouseDown, NSPoint(x: 10, y: 8)))
        guard began, completed.isEmpty else { throw SelfCheckFailure("Deck drag finishes before the mouse is released") }
        dragHandle.mouseDragged(with: dragEvent(.leftMouseDragged, NSPoint(x: 60, y: 38)))
        guard dragWindow.frame.origin == NSPoint(x: startFrame.minX + 50, y: startFrame.minY + 30), completed.isEmpty else {
            throw SelfCheckFailure("Deck does not follow the pointer until release")
        }
        dragHandle.mouseUp(with: dragEvent(.leftMouseUp, NSPoint(x: 10, y: 8)))
        dragHandle.mouseDown(with: dragEvent(.leftMouseDown, NSPoint(x: 10, y: 8)))
        dragHandle.mouseUp(with: dragEvent(.leftMouseUp, NSPoint(x: 10, y: 8)))
        guard completed == [true, false] else { throw SelfCheckFailure("Deck drops do not distinguish a drag from a click") }
        for fontName in ["Helvetica", "Virgil", "Caveat", "Comic Neue", "Bradley Hand", "Chalkboard SE", "Marker Felt", "Noteworthy", "Nunito", "Avenir Next", "American Typewriter", "Cascadia Code", "Inconsolata"] {
            for size in [10.0, 14.0, 21.0, 28.0] {
                for prefix in ["- [ ] ", "- [x] ~~"] {
                    guard let font = NSFont(name: fontName, size: size) else { continue }
                    let taskEditor = ChecklistNSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
                    taskEditor.noteFont = font
                    taskEditor.textContainer?.containerSize = NSSize(width: 150, height: 1000)
                    taskEditor.string = prefix + "Task alignment wraps cleanly onto another line with the same text inset" + (prefix.hasSuffix("~~") ? "~~" : "")
                    taskEditor.applyStyle()
                    guard let layout = taskEditor.layoutManager, let container = taskEditor.textContainer else {
                        throw SelfCheckFailure("Checklist layout is unavailable")
                    }
                    layout.ensureLayout(for: container)
                    let glyph = layout.glyphIndexForCharacter(at: prefix.count)
                    let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    let textCenter = taskEditor.textContainerOrigin.y + line.minY + layout.location(forGlyphAt: glyph).y - (font.ascender + font.descender) / 2
                    guard let checkbox = taskEditor.checkboxRect(at: 0), abs(checkbox.midY - textCenter) < 0.5 else {
                        throw SelfCheckFailure("Task checkbox is not aligned to \(fontName) at \(Int(size)) pt")
                    }
                    let textX = taskEditor.textContainerOrigin.x + line.minX + layout.location(forGlyphAt: glyph).x
                    guard (7...9).contains(textX - checkbox.maxX) else {
                        throw SelfCheckFailure("Task text does not have a consistent gap after its checkbox")
                    }
                    var lineCount = 0
                    var aligned = true
                    layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, range, _ in
                        lineCount += 1
                        if lineCount > 1 {
                            let wrappedX = taskEditor.textContainerOrigin.x + rect.minX + layout.location(forGlyphAt: range.location).x
                            if abs(wrappedX - textX) > 0.5 { aligned = false }
                        }
                    }
                    guard lineCount > 1, aligned else { throw SelfCheckFailure("Wrapped tasks do not align with the first line") }
                }
            }
        }
        let editor = ChecklistNSTextView()
        editor.noteFont = .systemFont(ofSize: 21)
        editor.string = "- [ ] First task"
        editor.applyStyle()
        guard (editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent == editor.checklistIndent,
              editor.selectedTextAttributes[.backgroundColor] != nil,
              editor.selectedTextAttributes[.foregroundColor] != nil else {
            throw SelfCheckFailure("Checklist alignment or selection styling does not match the note editor")
        }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertNewline(nil)
        guard editor.string == "- [ ] First task\n- [ ] " else {
            throw SelfCheckFailure("Return in a checklist item does not create the next task")
        }
        editor.string = "- [x] Finished"
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertNewline(nil)
        guard editor.string == "- [x] Finished\n- [ ] " else {
            throw SelfCheckFailure("Return after a completed task creates a completed item")
        }
        editor.string = "- [ ] "
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.applyStyle()
        if let layoutManager = editor.layoutManager, let textContainer = editor.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let line = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            guard line.height >= layoutManager.defaultLineHeight(for: editor.noteFont) * 0.9 else {
                throw SelfCheckFailure("An empty checklist item collapses its insertion cursor")
            }
        }
        editor.insertNewline(nil)
        guard editor.string.isEmpty else {
            throw SelfCheckFailure("Return on an empty checklist item does not end the list")
        }
        editor.string = "Body"
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertChecklistItem()
        guard editor.string == "Body\n- [ ] ", editor.selectedRange().location == (editor.string as NSString).length else {
            throw SelfCheckFailure("Adding a checklist item does not place the caret in the new task")
        }
        guard let typingFont = editor.typingAttributes[.font] as? NSFont, typingFont.pointSize == 21, editor.insertionPointColor.alphaComponent > 0.5 else {
            throw SelfCheckFailure("Checklist typing or insertion cursor is invisible")
        }
        editor.insertText("Second task", replacementRange: editor.selectedRange())
        guard editor.string == "Body\n- [ ] Second task" else {
            throw SelfCheckFailure("Typing after adding a checklist item writes at the wrong position")
        }
        editor.string = "["
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertText("]", replacementRange: editor.selectedRange())
        guard editor.string == "- [ ] ", editor.selectedRange().location == 6 else {
            throw SelfCheckFailure("Typing [] does not start a checklist")
        }
    }

    private static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        let convert: (CGFloat) -> CGFloat = { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * convert(rgb.redComponent)
            + 0.7152 * convert(rgb.greenComponent)
            + 0.0722 * convert(rgb.blueComponent)
    }
}
