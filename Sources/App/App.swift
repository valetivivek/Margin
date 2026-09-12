import AppKit
import Carbon
import Combine
import LocalAuthentication
import QuartzCore
import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications

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
        let width: CGFloat = count == 0 ? 40 : expanded ? expandedWidth : (bottom ? max(38, CGFloat(count) * 22 + 20) : 12)
        let height: CGFloat = count == 0 ? 40 : expanded ? expandedHeight : (bottom ? 12 : max(18, CGFloat(count) * 22 + 12))
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

    static func hasFullScreenWindow(on screen: CGRect, windows: [[String: Any]], ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> Bool {
        func bounds(_ window: [String: Any]) -> CGRect? {
            (window[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  window[kCGWindowLayer as String] as? Int == 0, let frame = bounds(window),
                  frame.minX <= screen.minX + 1, frame.maxX >= screen.maxX - 1,
                  frame.maxY >= screen.maxY - 1 else { return false }
            if frame.minY <= screen.minY + 1 { return true }
            // Helium splits fullscreen into a content window and its own menu-bar window.
            // A maximized desktop window has no matching companion and stays visible.
            // ponytail: match the current browser chrome geometry; revise if its window layout changes.
            let header = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: frame.minY - screen.minY)
            guard header.height <= 80 else { return false }
            return windows.contains { companion in
                guard companion[kCGWindowOwnerPID as String] as? Int32 == pid,
                      let layer = companion[kCGWindowLayer as String] as? Int, (24...30).contains(layer),
                      let frame = bounds(companion) else { return false }
                return frame.insetBy(dx: -1, dy: -1).contains(header)
            }
        }
    }
}

final class EdgePanelModel: ObservableObject {
    @Published var expanded = false
    @Published var fanVisible = false
    @Published var noteLimit = 8
    var dragging = false
    @Published var side: ScreenSide = .right
    var reorderingNote: UUID?
    let cardGesture = HeldCardGesture()
}

final class EdgePanelController: NSWindowController {
    static let expandedSize = NSSize(width: 480, height: 684)
    var screen: NSScreen
    let model = EdgePanelModel()
    private let settings: AppSettings
    private let store: NotesStore
    private var collapseWork: DispatchWorkItem?
    private var activationWork: DispatchWorkItem?
    private var notesObservation: AnyCancellable?
    private var hidden = false
    private var dockingPreview: NSPanel?
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    init(screen: NSScreen, store: NotesStore, settings: AppSettings, coordinator: AppCoordinator) {
        self.screen = screen
        self.settings = settings
        self.store = store
        model.side = settings.side
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
            hover: { [weak self] value in self?.setHovered(value) ?? false },
            beginDrag: { [weak self] in
                self?.model.dragging = true
                self?.activationWork?.cancel(); self?.collapseWork?.cancel()
            },
            draggingDeck: { [weak self] point in self?.previewDock(at: point) },
            endDrag: { [weak self] moved in
                guard let self, let frame = self.window?.frame else { return }
                self.dockingPreview?.orderOut(nil)
                guard moved else { self.model.dragging = false; self.refresh(); return }
                coordinator.dockDeck(self, at: NSEvent.mouseLocation, center: NSPoint(x: frame.midX, y: frame.midY))
            },
            create: { [weak self] in coordinator.createNote(on: self?.screen) },
            open: { [weak self] in $0 == CalendarWing.id ? coordinator.showCalendar() : coordinator.openEditor($0, on: self?.screen) },
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
        model.cardGesture.end()
        dockingPreview?.close()
        super.close()
    }

    private func previewDock(at point: NSPoint) {
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let side = DeckPlacement.nearestSide(to: point, in: target.frame) else {
            dockingPreview?.orderOut(nil)
            return
        }
        // Turn side-mounted cards inward before they pass off the opposite screen edge.
        if model.side != .bottom, side != .bottom, model.side != side, let window {
            model.side = side
            window.setFrameOrigin(NSPoint(x: side == .left ? point.x - 20 : point.x + 20 - window.frame.width,
                                          y: window.frame.minY))
            window.contentView?.layoutSubtreeIfNeeded()
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
                                        position: fraction, count: min(store.active.count + (settings.calendarEnabled ? 1 : 0), model.noteLimit), expanded: true)
        if side != .bottom {
            frame.size.width = DeckCardMetrics.visibleWidth
            frame.origin.x = side == .left ? target.frame.minX : target.frame.maxX - frame.width
        }
        (preview.contentView as? NSTextField)?.stringValue = side == .left ? "← Release to dock left" : side == .right ? "Release to dock right →" : "↓ Release to dock below"
        let appearing = !preview.isVisible
        if appearing { preview.setFrame(frame, display: true); preview.alphaValue = 0; preview.orderFrontRegardless() }
        preview.setFrame(frame, display: true)
        if appearing {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                preview.animator().alphaValue = 1
            }
        }
    }

    func setHidden(_ value: Bool) {
        guard hidden != value else { return }
        hidden = value
        if value {
            activationWork?.cancel(); activationWork = nil; collapseWork?.cancel()
            dockingPreview?.orderOut(nil)
            window?.orderOut(nil)
        } else { refresh() }
    }

    func refresh() {
        guard !model.dragging else { return }
        activationWork?.cancel(); activationWork = nil
        window?.collectionBehavior = DeckPlacement.collectionBehavior(overFullScreen: settings.showOverFullScreen).union([.stationary, .ignoresCycle])
        model.side = settings.side
        model.noteLimit = settings.side == .bottom
            ? min(8, max(1, Int((screen.visibleFrame.width - 160) / DeckCardMetrics.bottomStep)))
            : min(8, max(1, Int((screen.visibleFrame.height - 120 - DeckCardMetrics.height) / DeckCardMetrics.step) + 1))
        resize(expanded: settings.keepOpen || model.expanded)
        model.fanVisible = model.expanded
    }

    @discardableResult
    func setHovered(_ inside: Bool) -> Bool {
        let inside = inside || (window?.frame.contains(pointerLocation()) ?? false)
        guard !model.dragging, model.reorderingNote == nil, !hidden, (!store.active.isEmpty || settings.calendarEnabled) else { return inside }
        if !inside { activationWork?.cancel(); activationWork = nil; setExpanded(false); return false }
        collapseWork?.cancel()
        if model.expanded { model.fanVisible = true; return true }
        guard activationWork == nil else { return true }
        let work = DispatchWorkItem { [weak self] in
            self?.activationWork = nil
            self?.setExpanded(true)
        }
        activationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.activationDelay, execute: work)
        return true
    }

    func setExpanded(_ value: Bool) {
        guard !model.dragging, model.reorderingNote == nil, !hidden, (!store.active.isEmpty || settings.calendarEnabled) else { return }
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
                  Self.shouldCollapse(pointer: self.pointerLocation(), in: window.frame) else { return }
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

    func finishDock(on target: NSScreen) {
        guard let window else { return }
        let changedEdge = model.side != settings.side || screen != target
        screen = target
        model.side = settings.side
        model.expanded = true; model.fanVisible = true
        let frame = DeckPlacement.frame(screen: target.frame, visible: target.visibleFrame, side: settings.side,
                                        position: settings.deckPosition, count: min(store.active.count + (settings.calendarEnabled ? 1 : 0), model.noteLimit), expanded: true)
        // Keep the same visible panel through the drop. Do not replay the reveal animation.
        if changedEdge || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(frame, display: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.model.dragging = false
            self.refresh()
        }
    }

    private func resize(expanded: Bool) {
        guard let window else { return }
        model.expanded = expanded
        if !expanded { model.fanVisible = false }
        let frame = DeckPlacement.frame(screen: screen.frame, visible: screen.visibleFrame, side: settings.side,
                                        position: settings.deckPosition, count: min(store.active.count + (settings.calendarEnabled ? 1 : 0), model.noteLimit), expanded: expanded)
        window.setFrame(frame, display: true)
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
            archive: { [weak self] in self?.requestDismiss { store.archive(note.id) } },
            delete: { [weak self] in self?.requestDismiss { store.delete(note.id) } },
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
        let active = CalendarWing.items(notes: store.active, enabled: settings.calendarEnabled, position: settings.calendarPosition, limit: 8, color: settings.calendarColor)
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

    private func requestDismiss(action: (() -> Bool)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        window?.endEditing(for: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let action, !action() { self.isDismissing = false; return }
            self.finishDismiss()
        }
    }

    private func finishDismiss() {
        guard store.flush(noteID) else { isDismissing = false; return }
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
        guard let frame = window?.frame else { return }
        settings.rememberNotePosition(x: frame.origin.x, y: frame.origin.y)
        store.edit(noteID, immediate: true) {
            $0.pinned = pinned
            if pinned { $0.pinX = frame.origin.x; $0.pinY = frame.origin.y }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard Self.shouldRememberMove(hasFinishedOpening: remembersMoves, isDismissing: isDismissing),
              let frame = window?.frame else { return }
        settings.rememberNotePosition(x: frame.origin.x, y: frame.origin.y)
        guard store.note(noteID)?.pinned == true else { return }
        store.edit(noteID) { $0.pinX = frame.origin.x; $0.pinY = frame.origin.y }
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
    let libraryNavigation = NoteLibraryNavigation()
    private var settingsWindow: NSWindowController?
    private var calendarWindow: NSWindowController?
    private var onboarding: NSWindowController?
    private var deckHidden = false
    private var visibilityTimer: Timer?

    init(store: NotesStore, settings: AppSettings, cloudSync: CloudSyncController, updater: SPUUpdater) {
        self.store = store; self.settings = settings; self.cloudSync = cloudSync; self.updater = updater
        settings.onChange = { [weak self] in DispatchQueue.main.async {
            guard let self else { return }
            NSApp.appearance = self.settings.appearance.nsAppearance
            if !self.settings.calendarEnabled {
                self.calendarWindow?.close()
                self.calendarWindow = nil
            }
            self.refreshPanels()
        } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildPanels() }
        for event in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in self?.refreshDeckVisibility() }
        }
        // Browser fullscreen transitions can happen without an application or Space change.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshDeckVisibility() }
    }

    deinit { visibilityTimer?.invalidate() }

    func start() {
        // Cloud Sync is intentionally unavailable in this build.
        rebuildPanels()
        if AppRuntime.isTest {
            if CommandLine.arguments.contains("--settings-test") { showSettings(); return }
            if CommandLine.arguments.contains("--capsule-test") { return }
            showDeck()
            if CommandLine.arguments.contains("--deck-test") { return }
            showAllNotes(filter: CommandLine.arguments.contains("--archive-test") ? .archived : .all)
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
        refreshDeckVisibility()
    }

    private var targetScreens: [NSScreen] {
        Self.targetScreens(from: NSScreen.screens, main: NSScreen.screens.first, selection: settings.display, id: { $0.displayID })
    }

    func refreshPanels() {
        let targetIDs = Set(targetScreens.map(ObjectIdentifier.init))
        for id in Array(edges.keys) where !targetIDs.contains(id) { edges.removeValue(forKey: id)?.close() }
        for screen in targetScreens where edges[ObjectIdentifier(screen)] == nil {
            let controller = EdgePanelController(screen: screen, store: store, settings: settings, coordinator: self)
            edges[ObjectIdentifier(screen)] = controller
            controller.setHidden(deckHidden)
        }
        edges.values.forEach { $0.refresh() }
        editors.values.forEach { $0.refreshCollectionBehavior() }
        refreshDeckVisibility()
    }

    private func refreshDeckVisibility() {
        let windows = !deckHidden && !settings.showOverFullScreen
            ? CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [] : []
        for controller in edges.values {
            let display = (controller.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            controller.setHidden(deckHidden || (!settings.showOverFullScreen && DeckPlacement.hasFullScreenWindow(on: CGDisplayBounds(display), windows: windows)))
        }
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
        guard store.flushAll() else { return }
        deckHidden = hidden
        refreshDeckVisibility()
        editors.values.forEach { if hidden { $0.window?.orderOut(nil) } else { $0.window?.orderFrontRegardless() } }
    }

    func cycleDeckPosition() {
        let sides = ScreenSide.allCases
        settings.side = sides[(sides.firstIndex(of: settings.side)! + 1) % sides.count]
        settings.deckPosition = 0.5
        showDeck()
    }

    func dockDeck(_ controller: EdgePanelController, at point: NSPoint, center: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let side = DeckPlacement.nearestSide(to: point, in: screen.frame) else {
            controller.finishDock(on: controller.screen)
            return
        }
        let anchor = side == settings.side ? center : point
        settings.deckPosition = min(1, max(0, side == .bottom
            ? (anchor.x - screen.frame.minX) / screen.frame.width
            : (anchor.y - screen.frame.minY) / screen.frame.height))
        settings.side = side
        if settings.display != "all" { settings.display = screen.displayID }
        edges.removeValue(forKey: ObjectIdentifier(controller.screen))
        if let previous = edges.updateValue(controller, forKey: ObjectIdentifier(screen)), previous !== controller { previous.close() }
        controller.finishDock(on: screen)
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
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window, queue: .main) { [weak self] _ in
                // Keep the controller alive until AppKit finishes closing its window.
                let closing = self?.editors.removeValue(forKey: id)
                DispatchQueue.main.async { withExtendedLifetime(closing) {} }
            }
        }
        guard settings.lockNotes else { show(); return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your notes") { success, _ in
            if success { DispatchQueue.main.async(execute: show) }
        }
    }

    func showAllNotes(filter: NoteFilter = .all) {
        libraryNavigation.query = ""
        libraryNavigation.filter = filter
        if let allNotes {
            allNotes.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 786, height: 634), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.title = "All Notes"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: AllNotesView(store: store, navigation: libraryNavigation, open: { [weak self] in self?.openEditor($0) }))
        if AppRuntime.isTest, CommandLine.arguments.contains("--minimum-size-test") { window.setContentSize(window.contentMinSize) }
        let controller = NSWindowController(window: window); allNotes = controller
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.allNotes = nil }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func showArchive() { showAllNotes(filter: .archived) }

    func showCalendar() {
        guard settings.calendarEnabled else { return }
        if let calendarWindow { calendarWindow.window?.makeKeyAndOrderFront(nil); return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let size = NSSize(width: 680, height: 590)
        let x = settings.side == .left ? visible.minX + 8 : settings.side == .right ? visible.maxX - size.width - 8 : min(max(pointer.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = settings.side == .bottom ? visible.minY + 8 : min(max(pointer.y - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8)
        let window = KeyPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "Calendar"
        window.onEscape = { [weak self] in self?.calendarWindow?.close(); self?.calendarWindow = nil }
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.level = .floating; window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 540)
        window.collectionBehavior = DeckPlacement.collectionBehavior(overFullScreen: settings.showOverFullScreen)
        window.contentView = NSHostingView(rootView: CalendarAgendaView(settings: settings,
            close: { [weak self] in self?.calendarWindow?.close(); self?.calendarWindow = nil },
            openSettings: { [weak self] in
                guard let self else { return }
                let calendarWindow = self.calendarWindow
                self.showSettings()
                calendarWindow?.close(); self.calendarWindow = nil
            }))
        calendarWindow = NSWindowController(window: window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.calendarWindow = nil }
        window.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if let settingsWindow { settingsWindow.window?.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 880, height: 520)
        window.title = "Settings"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: SettingsView(settings: settings, store: store, cloudSync: cloudSync, updater: updater))
        hosting.sizingOptions = []
        window.contentView = hosting
        if AppRuntime.isTest, CommandLine.arguments.contains("--minimum-size-test") { window.setContentSize(window.contentMinSize) }
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
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
    let settings = AppSettings(defaults: AppRuntime.isTest
        ? UserDefaults(suiteName: "margin-ui-test-\(ProcessInfo.processInfo.processIdentifier)")! : .standard)
    lazy var store = NotesStore(settings: settings)
    lazy var cloudSync = CloudSyncController(store: store, settings: settings)
    private let updaterController = SPUStandardUpdaterController(startingUpdater: !AppRuntime.isTest, updaterDelegate: nil, userDriverDelegate: nil)
    lazy var coordinator = AppCoordinator(store: store, settings: settings, cloudSync: cloudSync, updater: updaterController.updater)
    private var hotKeys: HotKeyManager?
    private var shortcutObservation: AnyCancellable?
    private var recordingObservation: AnyCancellable?
    private var shortcutRecording = false
    private var dockObservation: AnyCancellable?
    private var statusIconObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var leftSideItem: NSMenuItem?
    private var rightSideItem: NSMenuItem?
    private var bottomSideItem: NSMenuItem?

    static func makeMainMenu(settings: AppSettings? = nil, target: AnyObject? = nil) -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let settingsShortcut = settings?.shortcut(for: .settings) ?? KeyboardAction.settings.standard
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(statusSettings(_:)), keyEquivalent: settings?.shortcutEnabled(.settings) == false ? "" : settingsShortcut.menuKey)
        settingsItem.keyEquivalentModifierMask = settingsShortcut.eventModifiers
        settingsItem.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let closeShortcut = settings?.shortcut(for: .close) ?? KeyboardAction.close.standard
        let closeItem = fileMenu.addItem(withTitle: "Close", action: #selector(statusCloseWindow(_:)), keyEquivalent: settings?.shortcutEnabled(.close) == false ? "" : closeShortcut.menuKey)
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
        editMenu.addItem(withTitle: "Bold", action: #selector(ChecklistNSTextView.boldSelection(_:)), keyEquivalent: "b")
        editMenu.addItem(withTitle: "Italic", action: #selector(ChecklistNSTextView.italicSelection(_:)), keyEquivalent: "i")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Start Dictation…", action: Selector(("startDictation:")), keyEquivalent: "")
        editMenu.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")
        editItem.submenu = editMenu
        return mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        updaterController.updater.sendsSystemProfile = false
        NSApp.appearance = settings.appearance.nsAppearance
        NSApp.setActivationPolicy(Self.activationPolicy(showInDock: settings.showInDock, uiTest: AppRuntime.isTest))
        NSApp.mainMenu = Self.makeMainMenu(settings: settings, target: self)
        if !AppRuntime.isTest { installHotKeys() }
        shortcutObservation = settings.$shortcuts.combineLatest(settings.$disabledShortcuts).dropFirst().sink { [weak self] _ in
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    static func activationPolicy(showInDock: Bool, uiTest: Bool) -> NSApplication.ActivationPolicy { showInDock ? .regular : .accessory }

    private func installHotKeys() {
        guard !shortcutRecording else { return }
        hotKeys = nil // Release old registrations before installing replacements.
        settings.shortcutError = nil
        let bindings: [(GlobalShortcut, () -> Void)] = KeyboardAction.allCases.filter { $0.isGlobal && settings.shortcutEnabled($0) }.map { action in
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
        statusIconObservation = settings.$menuBarIcon.sink { [weak item] symbol in
            item?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Margin")
            item?.button?.image?.isTemplate = true
        }
        item.button?.toolTip = "Margin"
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(statusNewNote(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "All Notes…", action: #selector(statusAllNotes(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Archive…", action: #selector(statusArchive(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Calendar…", action: #selector(statusCalendar(_:)), keyEquivalent: "")
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
        menu.item(withTitle: "Calendar…")?.isEnabled = settings.calendarEnabled
        leftSideItem?.state = settings.side == .left ? .on : .off
        rightSideItem?.state = settings.side == .right ? .on : .off
        bottomSideItem?.state = settings.side == .bottom ? .on : .off
    }

    @objc private func statusNewNote(_ sender: Any?) { coordinator.createNote() }
    @objc private func statusAllNotes(_ sender: Any?) { coordinator.showAllNotes() }
    @objc private func statusArchive(_ sender: Any?) { coordinator.showArchive() }
    @objc private func statusCalendar(_ sender: Any?) { coordinator.showCalendar() }
    @objc private func statusSettings(_ sender: Any?) { coordinator.showSettings() }
    @objc fileprivate func statusCloseWindow(_ sender: Any?) { (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(sender) }
    @objc private func statusToggleDeck(_ sender: Any?) { coordinator.toggleDeckHidden() }
    @objc private func statusShowDeck(_ sender: Any?) { coordinator.showDeck() }
    @objc private func statusCheckForUpdates(_ sender: Any?) { if !AppRuntime.isTest { updaterController.checkForUpdates(sender) } }
    @objc private func statusSideLeft(_ sender: Any?) { settings.side = .left }
    @objc private func statusSideRight(_ sender: Any?) { settings.side = .right }
    @objc private func statusSideBottom(_ sender: Any?) { settings.side = .bottom }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sender.keyWindow?.endEditing(for: nil)
        guard store.flushAll() else {
            let alert = NSAlert()
            alert.messageText = "Your latest changes could not be saved"
            alert.informativeText = store.errorMessage ?? "Keep Margin open and try again."
            alert.addButton(withTitle: "Keep Margin Open")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum AppSelfCheck {
    static func checkDeckHover(store: NotesStore, settings: AppSettings) throws {
        guard let screen = NSScreen.main else { throw SelfCheckFailure("No screen available for deck hover regression") }
        let updates = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let sync = CloudSyncController(store: store, settings: settings)
        let coordinator = AppCoordinator(store: store, settings: settings, cloudSync: sync, updater: updates.updater)
        let deck = EdgePanelController(screen: screen, store: store, settings: settings, coordinator: coordinator)
        defer { deck.close() }
        let survivorIDs = Set(store.notes.map(\.id))
        let deleted = store.create()
        coordinator.openEditor(deleted.id)
        RunLoop.current.run(until: Date().addingTimeInterval(settings.cardDuration + 0.1))
        guard let editor = NSApp.windows.compactMap({ $0.contentView as? NSHostingView<NoteEditorView> })
            .first(where: { $0.rootView.noteID == deleted.id }) else {
            throw SelfCheckFailure("Cannot open the note deletion regression editor")
        }
        editor.rootView.delete()
        RunLoop.current.run(until: Date().addingTimeInterval(settings.cardDuration + 0.2))
        guard Set(store.notes.map(\.id)) == survivorIDs else {
            throw SelfCheckFailure("Editor deletion changes unrelated notes")
        }
        coordinator.createNote()
        guard let createdID = settings.lastOpenNoteID, store.note(createdID) != nil,
              let reopened = NSApp.windows.first(where: {
                  ($0.contentView as? NSHostingView<NoteEditorView>)?.rootView.noteID == createdID && $0.isVisible
              }) else {
            throw SelfCheckFailure("Cannot create and open a note after deletion")
        }
        reopened.close()
        coordinator.showAllNotes()
        guard let library = NSApp.windows.first(where: { $0.title == "All Notes" }),
              let hosting = library.contentView as? NSHostingView<AllNotesView> else {
            throw SelfCheckFailure("All Notes did not open its library")
        }
        coordinator.libraryNavigation.query = "no matching notes"
        coordinator.showArchive()
        guard hosting.rootView.navigation.filter == .archived,
              hosting.rootView.navigation.query.isEmpty,
              NSApp.windows.filter({ $0.title == "All Notes" && $0.isVisible }).count == 1,
              !NSApp.windows.contains(where: { $0.title == "Archive" && $0.isVisible }) else {
            throw SelfCheckFailure("Archive did not reuse and retarget the library")
        }
        coordinator.showAllNotes()
        guard hosting.rootView.navigation.filter == .all, library.isVisible else {
            throw SelfCheckFailure("All Notes did not reset the open library filter")
        }
        library.close()
        coordinator.showArchive()
        guard coordinator.libraryNavigation.filter == .archived,
              NSApp.windows.contains(where: { $0.title == "All Notes" && $0.isVisible }) else {
            throw SelfCheckFailure("Archive could not reopen the shared library")
        }
        NSApp.windows.first(where: { $0.title == "All Notes" && $0.isVisible })?.close()
        settings.calendarEnabled = true
        coordinator.showCalendar()
        guard let calendar = NSApp.windows.first(where: { $0.title == "Calendar" }) else {
            throw SelfCheckFailure("Margin Calendar cannot open")
        }
        settings.calendarEnabled = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard !calendar.isVisible else {
            throw SelfCheckFailure("Turning off Calendar leaves its window open")
        }
        coordinator.showCalendar()
        guard !NSApp.windows.contains(where: { $0.title == "Calendar" && $0.isVisible }) else {
            throw SelfCheckFailure("Margin Calendar opens while disabled")
        }
        settings.calendarEnabled = true
        coordinator.showCalendar()
        guard NSApp.windows.contains(where: { $0.title == "Calendar" && $0.isVisible }) else {
            throw SelfCheckFailure("Margin Calendar cannot reopen after being enabled")
        }
        NSApp.windows.first(where: { $0.title == "Calendar" })?.close()
        deck.setExpanded(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let frame = deck.window!.frame
        deck.pointerLocation = { NSPoint(x: frame.midX, y: frame.midY) }
        deck.setHovered(false)
        guard deck.model.fanVisible else { throw SelfCheckFailure("The whole deck retracts on a false exit while the pointer is inside its panel") }
        deck.pointerLocation = { NSPoint(x: frame.minX - 20, y: frame.minY - 20) }
        deck.setHovered(false)
        guard !deck.model.fanVisible else { throw SelfCheckFailure("The deck does not retract after a real pointer exit") }
    }

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
        func externalWindow(_ frame: CGRect, layer: Int = 0, pid: Int32 = 101) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowBounds as String: frame.dictionaryRepresentation]
        }
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let browser = externalWindow(CGRect(x: 0, y: 30, width: 2560, height: 1410))
        let browserMenu = externalWindow(CGRect(x: 0, y: 0, width: 2560, height: 30), layer: 26)
        let otherDisplay = CGRect(x: -1710, y: 0, width: 1710, height: 1112)
        guard DeckPlacement.hasFullScreenWindow(on: display, windows: [externalWindow(display)]),
              DeckPlacement.hasFullScreenWindow(on: display, windows: [browser, browserMenu]),
              !DeckPlacement.hasFullScreenWindow(on: display, windows: [browser]),
              !DeckPlacement.hasFullScreenWindow(on: display, windows: [browser, externalWindow(CGRect(x: 0, y: 0, width: 2560, height: 30), layer: 26, pid: 102)]),
              !DeckPlacement.hasFullScreenWindow(on: display, windows: [externalWindow(display)], ownPID: 101),
              !DeckPlacement.hasFullScreenWindow(on: otherDisplay, windows: [browser, browserMenu]),
              DeckPlacement.hasFullScreenWindow(on: otherDisplay, windows: [externalWindow(otherDisplay)]) else {
            throw SelfCheckFailure("Fullscreen visibility confuses Helium, maximized windows, or another display")
        }
        var privateNote = Note(); privateNote.title = "Private title"; privateNote.body = "Private body"
        guard SettingsView.previewContent(notes: [privateNote], locked: false, index: 0).body == privateNote.body,
              SettingsView.previewContent(notes: [privateNote], locked: true, index: 0).body != privateNote.body,
              !SettingsView.previewContent(notes: [], locked: false, index: 0).body.isEmpty else {
            throw SelfCheckFailure("Settings preview ignores real notes or exposes locked notes")
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
        for isDark in [false, true] {
            let background = SettingsPalette.color(isDark ? 0x23231F : 0xF3F1EC)
            let secondary = SettingsPalette.color(isDark ? 0xB8B4A9 : 0x65625B)
            guard contrastRatio(secondary, background) >= 4.5,
                  InterfaceColor.allCases.allSatisfy({ contrastRatio($0.nsColor(isDark: isDark), background) >= 4.5 }) else {
                throw SelfCheckFailure("Settings colors do not have enough contrast")
            }
        }
        guard NSFont(name: "Satoshi-Regular", size: 13) != nil,
              NSFont(name: "Satoshi-Medium", size: 13) != nil else {
            throw SelfCheckFailure("Settings typography is missing from the app bundle")
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
              DeckCardMetrics.hoverHeight(lifted: false, isLast: true) == 152 else {
            throw SelfCheckFailure("Deck hover targets do not match the stationary note slots")
        }
        guard NSApp != nil else { return }
        let markdownEditor = ChecklistNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        markdownEditor.markdownEnabled = true
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
        let sourceBeforeEditing = markdownEditor.string
        markdownEditor.beginSourceEditing()
        guard !markdownEditor.isPreview,
              (markdownEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 16,
              markdownEditor.checkboxRect(at: (markdownEditor.string as NSString).range(of: "- [ ]").location) == nil else {
            throw SelfCheckFailure("Editing mode still hides Markdown or draws preview checkboxes")
        }
        markdownEditor.showPreview()
        guard markdownEditor.isPreview, markdownEditor.string == sourceBeforeEditing,
              (markdownEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 0.01 else {
            throw SelfCheckFailure("Returning to preview changes source or fails to format")
        }
        for side in ScreenSide.allCases {
            let empty = DeckPlacement.frame(screen: screen, visible: screen, side: side, position: 0.5, count: 0, expanded: false)
            guard empty.size == NSSize(width: 40, height: 40), screen.contains(empty) else {
                throw SelfCheckFailure("Empty deck does not fit its single Add button")
            }
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
        let timedEditor = ChecklistNSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        timedEditor.markdownEnabled = true
        timedEditor.string = "## Idle preview"
        timedEditor.previewDelay = 0.01
        dragWindow.contentView = timedEditor
        dragWindow.makeFirstResponder(timedEditor)
        timedEditor.beginSourceEditing()
        timedEditor.setSelectedRange(NSRange(location: (timedEditor.string as NSString).length, length: 0))
        let previewDeadline = Date().addingTimeInterval(2)
        while !timedEditor.isPreview, Date() < previewDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard timedEditor.isPreview, timedEditor.string == "## Idle preview" else {
            throw SelfCheckFailure("Idle timer does not return to preview losslessly (selection: \(timedEditor.selectedRange()), marked text: \(timedEditor.hasMarkedText()), mouse buttons: \(NSEvent.pressedMouseButtons))")
        }
        dragWindow.contentView = dragHandle
        var began = false
        var completed: [Bool] = []
        dragHandle.screenPointer = { dragWindow.convertPoint(toScreen: $0.locationInWindow) }
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
        // Moving/reorienting the window must not feed back into the next pointer delta.
        var pointer = NSPoint(x: 800, y: 400)
        dragHandle.screenPointer = { _ in pointer }
        dragHandle.mouseDown(with: dragEvent(.leftMouseDown, .zero))
        pointer.x = 30
        dragHandle.mouseDragged(with: dragEvent(.leftMouseDragged, .zero))
        dragWindow.setFrameOrigin(NSPoint(x: 10, y: 200))
        pointer.x = 25
        dragHandle.mouseDragged(with: dragEvent(.leftMouseDragged, NSPoint(x: 999, y: 0)))
        guard dragWindow.frame.minX == 5 else { throw SelfCheckFailure("Reorienting left feeds window motion into pointer tracking") }
        pointer.x = 800
        dragHandle.mouseDragged(with: dragEvent(.leftMouseDragged, .zero))
        guard dragWindow.frame.minX == 780 else { throw SelfCheckFailure("Rightward drag uses stale window coordinates") }
        dragHandle.mouseUp(with: dragEvent(.leftMouseUp, .zero))

        let card = DeckCardInteractionView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        dragWindow.contentView = card
        var wingHovered = false
        card.hover = { wingHovered = $0 }
        card.mouseEntered(with: dragEvent(.mouseMoved, NSPoint(x: 50, y: 50)))
        card.mouseExited(with: dragEvent(.mouseMoved, NSPoint(x: 50, y: 50)))
        guard wingHovered else { throw SelfCheckFailure("Wing retracts on a tracking-area exit while the pointer is still inside") }
        card.mouseExited(with: dragEvent(.mouseMoved, NSPoint(x: 150, y: 50)))
        guard !wingHovered else { throw SelfCheckFailure("Wing stays hovered after the pointer leaves") }
        var moves: [Int] = []
        var opens = 0
        card.reorder = { moves.append($0) }; card.activate = { opens += 1 }
        card.mouseDown(with: dragEvent(.leftMouseDown, NSPoint(x: 10, y: 10)))
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)!
        card.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        card.mouseUp(with: dragEvent(.leftMouseUp, NSPoint(x: 10, y: 10)))
        guard moves.count == 1, opens == 0 else { throw SelfCheckFailure("Held-card scrolling opens the note or fails to reorder") }
        card.mouseDown(with: dragEvent(.leftMouseDown, NSPoint(x: 10, y: 10)))
        card.mouseUp(with: dragEvent(.leftMouseUp, NSPoint(x: 10, y: 10)))
        guard opens == 1 else { throw SelfCheckFailure("Normal card clicks stopped opening notes") }
        // A hold belongs to the deck, even when SwiftUI detaches/replaces its card view.
        let held = HeldCardGesture()
        card.gesture = held
        moves = []
        card.mouseDown(with: dragEvent(.leftMouseDown, NSPoint(x: 10, y: 10)))
        for _ in 0..<4 { card.scrollWheel(with: NSEvent(cgEvent: wheel)!) }
        guard moves == [-1, -1, -1, -1] else { throw SelfCheckFailure("Mouse-wheel reordering has the wrong direction or drops rapid ticks") }
        dragWindow.contentView = NSView()
        held.scroll(with: NSEvent(cgEvent: wheel)!)
        let reverseWheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        held.scroll(with: NSEvent(cgEvent: reverseWheel)!)
        guard held.active, moves.count == 6, moves[4] == -moves[5] else {
            throw SelfCheckFailure("Card relocation ends a hold or loses a quick wheel reversal")
        }
        held.end()
        held.scroll(with: NSEvent(cgEvent: wheel)!)
        guard moves.count == 6 else { throw SelfCheckFailure("Reordering continues after release") }
        moves = []
        held.begin(reorder: { moves.append($0) }, finished: {})
        let precise = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -5, wheel2: 0, wheel3: 0)!
        for _ in 0..<4 { held.scroll(with: NSEvent(cgEvent: precise)!) }
        guard moves == [-1] else { throw SelfCheckFailure("Trackpad reordering has the wrong direction or loses small deltas") }
        held.end()
        timedEditor.beginSourceEditing()
        timedEditor.mouseExited(with: dragEvent(.mouseMoved, .zero))
        guard timedEditor.isPreview else { throw SelfCheckFailure("Leaving a note does not return to preview") }
        let deckPreview = String(NoteMarkdown.preview("## Heading\n**Bold**\n- [ ] Task", font: .systemFont(ofSize: 16)).characters)
        guard deckPreview.contains("Heading"), deckPreview.contains("Bold"), deckPreview.contains("☐ Task"), !deckPreview.contains("##"), !deckPreview.contains("**") else {
            throw SelfCheckFailure("Deck cards expose raw Markdown markers")
        }
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
                    let textCenter = taskEditor.textContainerOrigin.y + line.minY + layout.location(forGlyphAt: glyph).y - font.capHeight / 2
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
        for markdown in [false, true] {
            let bullets = ChecklistNSTextView()
            bullets.markdownEnabled = markdown
            bullets.string = "-"
            bullets.setSelectedRange(NSRange(location: 1, length: 0))
            bullets.insertText(" ", replacementRange: bullets.selectedRange())
            guard bullets.string == "• " else { throw SelfCheckFailure("Dash-space does not start a bullet") }
            bullets.insertText("😀 item", replacementRange: bullets.selectedRange())
            bullets.insertNewline(nil)
            guard bullets.string == "• 😀 item\n• " else { throw SelfCheckFailure("Return does not continue bullets") }
            bullets.insertNewline(nil)
            guard bullets.string == "• 😀 item\n" else { throw SelfCheckFailure("Double Return does not end bullets") }
            bullets.string = "ordinary -"
            bullets.setSelectedRange(NSRange(location: 10, length: 0))
            bullets.insertText(" ", replacementRange: bullets.selectedRange())
            guard bullets.string == "ordinary - " else { throw SelfCheckFailure("Inline hyphens are converted to bullets") }
        }
        for text in ["Plain text", "- [ ] Task text"] {
            for trait in [NSFontTraitMask.boldFontMask, .italicFontMask] {
                let toggleEditor = ChecklistNSTextView()
                toggleEditor.string = text
                toggleEditor.applyStyle()
                for selection in [NSRange(location: 0, length: (text as NSString).length), NSRange(location: (text as NSString).length, length: 0)] {
                    toggleEditor.setSelectedRange(selection)
                    toggleEditor.format(trait: trait)
                    toggleEditor.format(trait: trait)
                    let font = (selection.length == 0 ? toggleEditor.typingAttributes[.font] : toggleEditor.textStorage?.attribute(.font, at: (text as NSString).length - 1, effectiveRange: nil)) as! NSFont
                    guard !NSFontManager.shared.traits(of: font).contains(trait) else {
                        throw SelfCheckFailure("Repeating a formatting shortcut does not turn it off in normal text or tasks")
                    }
                }
            }
        }
        let calendarNotes = (0..<10).map { Note(title: "Note \($0)") }
        for position in [0, 3, Int.max] {
            let items = CalendarWing.items(notes: calendarNotes, enabled: true, position: position, limit: 8)
            let expectedPosition = min(position, 7)
            guard items.count == 8, items[expectedPosition].id == CalendarWing.id,
                  items.filter({ $0.id != CalendarWing.id }).map(\.id) == Array(calendarNotes.prefix(7)).map(\.id),
                  CalendarWing.items(notes: [], enabled: true, position: position, limit: 8).count == 1,
                  CalendarWing.items(notes: calendarNotes, enabled: false, position: position, limit: 8).map(\.id) == Array(calendarNotes.prefix(8)).map(\.id) else {
                throw SelfCheckFailure("Calendar wing placement or note order is incorrect")
            }
        }
        guard CalendarWing.movedPosition(0, by: 3, noteCount: 10, limit: 8) == 3,
              CalendarWing.movedPosition(7, by: 1, noteCount: 10, limit: 8) == 7,
              CalendarWing.movedPosition(Int.max, by: 1, noteCount: 10, limit: 8) == 7,
              CalendarWing.movedPosition(2, by: -9, noteCount: 10, limit: 8) == 0 else {
            throw SelfCheckFailure("Calendar wing dragging escapes the visible deck")
        }
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstDay = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        guard CalendarAgenda.dayRange(dstDay, calendar: dstCalendar).duration == 23 * 3600 else {
            throw SelfCheckFailure("Calendar date navigation loses daylight-saving boundaries")
        }
        let now = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10, minute: 12, second: 42))!
        let later = CalendarAgenda.defaultEventStart(for: now, now: now, calendar: dstCalendar)
        let tomorrow = dstCalendar.date(byAdding: .day, value: 1, to: now)!
        guard dstCalendar.component(.hour, from: later) == 10,
              dstCalendar.component(.minute, from: later) == 30,
              dstCalendar.component(.second, from: later) == 0,
              dstCalendar.component(.hour, from: CalendarAgenda.defaultEventStart(for: tomorrow, now: now, calendar: dstCalendar)) == 9 else {
            throw SelfCheckFailure("New calendar events do not start at a useful time")
        }
        guard CalendarAgenda.reminderAlarms(minutes: -2) == nil,
              CalendarAgenda.reminderAlarms(minutes: -1)?.isEmpty == true,
              CalendarAgenda.reminderAlarms(minutes: 0)?.first?.relativeOffset == 0,
              CalendarAgenda.reminderAlarms(minutes: 10)?.first?.relativeOffset == -600 else {
            throw SelfCheckFailure("Calendar reminder offsets or preservation are incorrect")
        }
        guard CalendarAlerts.fireDate(start: now, alarms: CalendarAgenda.reminderAlarms(minutes: 0)) == now,
              CalendarAlerts.fireDate(start: now, alarms: CalendarAgenda.reminderAlarms(minutes: 10)) == now.addingTimeInterval(-600),
              CalendarAlerts.fireDate(start: now, alarms: CalendarAgenda.reminderAlarms(minutes: -1)) == nil else {
            throw SelfCheckFailure("Calendar app notification times are incorrect")
        }
        let invalidEvent = CalendarAgenda.eventDates(start: dstDay, end: dstDay.addingTimeInterval(-1), allDay: false, calendar: dstCalendar)
        let allDayEvent = CalendarAgenda.eventDates(start: dstDay.addingTimeInterval(3600), end: dstDay, allDay: true, calendar: dstCalendar)
        guard invalidEvent == nil, allDayEvent?.0 == dstDay, allDayEvent?.1 == dstCalendar.date(byAdding: .day, value: 1, to: dstDay) else {
            throw SelfCheckFailure("New calendar events use invalid dates")
        }
        guard CalendarAgenda.visibleCalendarIDs(current: ["Home"], saved: "Google") == ["Home", "Google"],
              CalendarAgenda.visibleCalendarIDs(current: [], saved: "Google") == [] else {
            throw SelfCheckFailure("A newly added event can stay hidden by the calendar filter")
        }
        let monthDays = CalendarAgenda.monthDays(dstDay, calendar: dstCalendar)
        guard monthDays.count == 42, Set(monthDays).count == 42,
              dstCalendar.component(.weekday, from: monthDays[0]) == dstCalendar.firstWeekday,
              monthDays.filter({ dstCalendar.component(.month, from: $0) == 3 }).count == 31 else {
            throw SelfCheckFailure("Calendar month grid drops or duplicates dates")
        }

        let bulletEditor = ChecklistNSTextView()
        bulletEditor.noteFont = NSFont.systemFont(ofSize: 21)
        bulletEditor.string = "-"
        bulletEditor.appearance = NSAppearance(named: .darkAqua)
        bulletEditor.applyStyle()
        bulletEditor.setSelectedRange(NSRange(location: 1, length: 0))
        bulletEditor.insertText(" ", replacementRange: bulletEditor.selectedRange())
        bulletEditor.setSelectedRange(NSRange(location: 2, length: 0))
        bulletEditor.insertText("Bullet text", replacementRange: bulletEditor.selectedRange())
        bulletEditor.applyStyle()
        bulletEditor.setSelectedRange(NSRange(location: 2, length: 6))
        bulletEditor.boldSelection(nil)
        bulletEditor.textStorage?.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: 13))
        bulletEditor.typingAttributes[.foregroundColor] = NSColor.white
        bulletEditor.applyStyle()
        bulletEditor.applyStyle()
        let bulletFont = bulletEditor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let bodyFont = bulletEditor.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        guard !bulletEditor.usesAdaptiveColorMappingForDarkAppearance,
              bulletEditor.textStorage!.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == NSColor.black,
              bulletEditor.typingAttributes[.foregroundColor] as? NSColor == NSColor.black,
              abs(bulletFont.pointSize - bodyFont.pointSize * 1.3) < 0.01 else {
            throw SelfCheckFailure("Pastel notes lose black text or stable enlarged bullets in dark appearance")
        }
        let savedBody = NSAttributedString(string: "Saved body", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let savedBodyData = try savedBody.data(from: NSRange(location: 0, length: savedBody.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let resizedEditor = ChecklistNSTextView()
        resizedEditor.noteFont = .systemFont(ofSize: 21); resizedEditor.string = savedBody.string
        resizedEditor.loadRichText(savedBodyData, baseSize: 12); resizedEditor.applyStyle()
        guard (resizedEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 21 else {
            throw SelfCheckFailure("Saved rich text overrides the selected note text size")
        }
        let richEditor = ChecklistNSTextView()
        dragWindow.contentView = richEditor
        dragWindow.makeFirstResponder(richEditor)
        guard !richEditor.markdownEnabled else { throw SelfCheckFailure("The normal editor enables Markdown by default") }
        richEditor.allowsUndo = true
        richEditor.string = "Bold and italic"
        richEditor.applyStyle()
        richEditor.setSelectedRange(NSRange(location: 0, length: 4))
        richEditor.boldSelection(nil)
        func richFont(_ index: Int) -> NSFont { richEditor.textStorage!.attribute(.font, at: index, effectiveRange: nil) as! NSFont }
        guard NSFontManager.shared.traits(of: richFont(0)).contains(.boldFontMask), richEditor.string == "Bold and italic" else {
            throw SelfCheckFailure("Native bold inserts Markdown or loses its font")
        }
        richEditor.setSelectedRange(NSRange(location: 9, length: 6))
        richEditor.italicSelection(nil)
        guard NSFontManager.shared.traits(of: richFont(9)).contains(.italicFontMask) else { throw SelfCheckFailure("Native italic is missing") }
        richEditor.setSelectedRange(NSRange(location: 0, length: 4))
        richEditor.format(heading: 1)
        guard richFont(0).pointSize > richEditor.noteFont.pointSize else { throw SelfCheckFailure("Heading does not enlarge selected text") }
        for name in ["Virgil", "Caveat", "Helvetica"] {
            if let font = NSFont(name: name, size: 21) {
                guard NSFontManager.shared.traits(of: NoteMarkdown.adding(.boldFontMask, to: font)).contains(.boldFontMask),
                      NSFontManager.shared.traits(of: NoteMarkdown.adding(.italicFontMask, to: font)).contains(.italicFontMask) else {
                    throw SelfCheckFailure("Formatting silently fails for a note typeface")
                }
            }
        }
        let richData = richEditor.richData()
        let reopenedEditor = ChecklistNSTextView()
        reopenedEditor.markdownEnabled = false; reopenedEditor.string = richEditor.string
        reopenedEditor.loadRichText(richData); reopenedEditor.applyStyle()
        guard (reopenedEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == richFont(0).pointSize else {
            throw SelfCheckFailure("Reopening loses native rich formatting")
        }
        richEditor.setSelectedRange(NSRange(location: 15, length: 0))
        richEditor.insertText("!", replacementRange: richEditor.selectedRange())
        guard richFont(0).pointSize > richEditor.noteFont.pointSize else { throw SelfCheckFailure("Typing clears existing formatting") }
        richEditor.setSelectedRange(NSRange(location: 0, length: 4))
        richEditor.undoManager?.removeAllActions()
        richEditor.undoManager?.beginUndoGrouping()
        richEditor.format(heading: 0)
        richEditor.undoManager?.endUndoGrouping()
        richEditor.undoManager?.undoNestedGroup()
        guard richFont(0).pointSize > richEditor.noteFont.pointSize else { throw SelfCheckFailure("Undo does not restore text formatting") }
        richEditor.string = "- [ ] Keep bold"
        richEditor.loadRichText(nil)
        richEditor.applyStyle()
        richEditor.setSelectedRange(NSRange(location: 6, length: 9))
        richEditor.boldSelection(nil)
        for checked in [true, false] {
            guard let box = richEditor.checkboxRect(at: 0) else { throw SelfCheckFailure("Native task has no checkbox") }
            let point = richEditor.convert(NSPoint(x: box.midX, y: box.midY), to: nil)
            richEditor.mouseDown(with: dragEvent(.leftMouseDown, point))
            guard richEditor.string.hasPrefix(checked ? "- [x] " : "- [ ] "),
                  NSFontManager.shared.traits(of: richFont(6)).contains(.boldFontMask),
                  (richEditor.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) != nil) == checked else {
                throw SelfCheckFailure("Task toggle failed: \(richEditor.string), traits: \(NSFontManager.shared.traits(of: richFont(6))), checked: \(checked)")
            }
        }
        guard NoteIcons.all.allSatisfy({ NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) else {
            throw SelfCheckFailure("An offered note icon is unavailable")
        }
        let editorHandle = ChecklistEditorHandle()
        var boundText = "Mode switch"
        var boundRichText: Data?
        func hostedEditor(markdown: Bool) -> ChecklistTextEditor {
            ChecklistTextEditor(text: Binding(get: { boundText }, set: { boundText = $0 }),
                richText: Binding(get: { boundRichText }, set: { boundRichText = $0 }),
                font: .systemFont(ofSize: 21), markdownEnabled: markdown, cancel: {}, handle: editorHandle)
        }
        let hosted = NSHostingView(rootView: hostedEditor(markdown: true))
        dragWindow.contentView = hosted
        hosted.layoutSubtreeIfNeeded()
        hosted.rootView = hostedEditor(markdown: false)
        hosted.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        guard let liveEditor = editorHandle.view, !liveEditor.markdownEnabled, liveEditor.isRichText else {
            throw SelfCheckFailure("Switching Markdown off does not update the hosted native editor")
        }
        liveEditor.setSelectedRange(NSRange(location: 0, length: 4))
        liveEditor.boldSelection(nil)
        guard boundText == "Mode switch", boundRichText != nil else {
            throw SelfCheckFailure("Hosted native formatting writes Markdown or fails to save")
        }
        let sourceTask = ChecklistNSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 200))
        sourceTask.markdownEnabled = true
        sourceTask.string = "- [ ] A long task that wraps while editing"
        sourceTask.beginSourceEditing()
        let sourceParagraph = sourceTask.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        guard (sourceParagraph?.headIndent ?? 0) > 0 else {
            throw SelfCheckFailure("Wrapped tasks lose their indentation in source editing")
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
