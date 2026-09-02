import AppKit
import Carbon
import Combine
import LocalAuthentication
import QuartzCore
import ServiceManagement
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

    init(shortcut: GlobalShortcut, quick: @escaping () -> Void, all: @escaping () -> Void) {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(), hotKeyCallback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        register(id: 1, key: shortcut.keyCode, modifiers: shortcut.modifiers, action: quick)
        register(id: 2, key: UInt32(kVK_ANSI_L), action: all)
    }

    deinit {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }

    private func register(id: UInt32, key: UInt32, modifiers: UInt32 = UInt32(cmdKey | optionKey), action: @escaping () -> Void) {
        actions[id] = action
        var ref: EventHotKeyRef?
        let signature: OSType = 0x484D4E54 // HMNT
        RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
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

final class EdgePanelModel: ObservableObject {
    @Published var expanded = false
    @Published var fanVisible = false
}

final class EdgePanelController: NSWindowController {
    static let expandedSize = NSSize(width: 480, height: 684)
    static let bottomExpandedSize = NSSize(width: 960, height: 280)
    let screen: NSScreen
    let model = EdgePanelModel()
    private let settings: AppSettings
    private var collapseWork: DispatchWorkItem?

    init(screen: NSScreen, store: NotesStore, settings: AppSettings, coordinator: AppCoordinator) {
        self.screen = screen
        self.settings = settings
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init(window: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = collectionBehavior()
        let hostingView = NSHostingView(rootView: EdgeDeckView(
            store: store,
            settings: settings,
            model: model,
            expand: { [weak self] value in self?.setExpanded(value) },
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
        panel.orderFrontRegardless()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func collectionBehavior() -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if settings.showOverFullScreen { behavior.insert(.fullScreenAuxiliary) }
        return behavior
    }

    func refresh() {
        window?.collectionBehavior = collectionBehavior()
        guard let window else { return }
        let expanded = settings.keepOpen || (model.expanded && !Self.shouldCollapse(pointer: NSEvent.mouseLocation, in: window.frame))
        resize(expanded: expanded)
        model.fanVisible = expanded
    }

    func setExpanded(_ value: Bool) {
        collapseWork?.cancel()
        if value {
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
        collapseWork?.cancel()
        guard !settings.keepOpen else { return }
        model.fanVisible = false
        resize(expanded: false)
    }

    static func shouldCollapse(pointer: NSPoint, in frame: NSRect) -> Bool {
        !frame.insetBy(dx: -2, dy: -2).contains(pointer)
    }

    private func resize(expanded: Bool) {
        guard let window else { return }
        model.expanded = expanded
        if !expanded { model.fanVisible = false }
        let width: CGFloat
        let height: CGFloat
        let x: CGFloat
        let y: CGFloat
        if settings.side == .bottom {
            width = expanded ? min(Self.bottomExpandedSize.width, screen.visibleFrame.width) : 220
            height = expanded ? min(Self.bottomExpandedSize.height, screen.visibleFrame.height) : 18
            x = screen.visibleFrame.midX - width / 2
            y = screen.frame.minY
        } else {
            width = expanded ? Self.expandedSize.width : 18
            height = expanded ? min(Self.expandedSize.height, screen.visibleFrame.height) : 220
            x = settings.side == .right ? screen.frame.maxX - width : screen.frame.minX
            y = screen.visibleFrame.midY - height / 2
        }
        let frame = NSRect(x: x, y: y, width: width, height: height)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }
}

final class StickyWindowController: NSWindowController, NSWindowDelegate {
    let noteID: UUID
    private let store: NotesStore
    private let screen: NSScreen
    private let settings: AppSettings
    private var deckFrame = NSRect.zero
    private var isDismissing = false
    private var remembersMoves = false
    private var escapeMonitor: Any?

    init(note: Note, screen: NSScreen, store: NotesStore, settings: AppSettings, coordinator: AppCoordinator) {
        noteID = note.id
        self.store = store
        self.screen = screen
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
        panel.collectionBehavior = settings.showOverFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces]
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
        let index = active.firstIndex(where: { $0.id == note.id }) ?? max(0, active.count - 1)
        let slotOffset = (CGFloat(index) - CGFloat(max(0, min(active.count, 8) - 1)) / 2) * (settings.side == .bottom ? DeckCardMetrics.bottomStep : DeckCardMetrics.step)
        if settings.side == .bottom {
            deckFrame = NSRect(
                x: screen.visibleFrame.midX + slotOffset - DeckCardMetrics.visibleWidth / 2,
                y: screen.frame.minY,
                width: DeckCardMetrics.visibleWidth,
                height: DeckCardMetrics.height
            )
        } else {
            deckFrame = NSRect(
                x: settings.side == .right ? screen.visibleFrame.maxX - DeckCardMetrics.width : screen.visibleFrame.minX,
                y: screen.visibleFrame.midY + slotOffset - DeckCardMetrics.height / 2,
                width: DeckCardMetrics.width,
                height: DeckCardMetrics.height
            )
        }
        let morph = !note.pinned && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(morph ? deckFrame : targetFrame, display: true)
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
        window?.collectionBehavior = settings.showOverFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces]
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
        guard remembersMoves, let frame = window?.frame else { return }
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
    private var edges: [ObjectIdentifier: EdgePanelController] = [:]
    private var editors: [UUID: StickyWindowController] = [:]
    private var allNotes: NSWindowController?
    private var archiveWindow: NSWindowController?
    private var settingsWindow: NSWindowController?
    private var onboarding: NSWindowController?

    init(store: NotesStore, settings: AppSettings, cloudSync: CloudSyncController) {
        self.store = store; self.settings = settings; self.cloudSync = cloudSync
        settings.onChange = { [weak self] in DispatchQueue.main.async {
            guard let self else { return }
            NSApp.appearance = self.settings.appearance.nsAppearance
            self.refreshPanels()
        } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildPanels() }
    }

    func start() {
        cloudSync.start()
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
        else { restorePinned() }
    }

    func rebuildPanels() {
        edges.values.forEach { $0.close() }; edges.removeAll()
        for screen in NSScreen.screens {
            let controller = EdgePanelController(screen: screen, store: store, settings: settings, coordinator: self)
            edges[ObjectIdentifier(screen)] = controller
        }
    }

    func refreshPanels() {
        edges.values.forEach { $0.refresh() }
        editors.values.forEach { $0.refreshCollectionBehavior() }
    }

    func showDeck() { edges.values.forEach { $0.setExpanded(true) } }

    func performQuickAction() {
        if settings.shortcutAction == .newNote { createNote(); return }
        if let note = store.active.first { openEditor(note.id) } else { createNote() }
    }

    func createNote(on screen: NSScreen? = nil) {
        let note = store.create()
        openEditor(note.id, on: screen ?? NSScreen.main)
    }

    func openEditor(_ id: UUID, on screen: NSScreen? = nil) {
        guard let note = store.note(id), let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        edges[ObjectIdentifier(targetScreen)]?.collapseImmediately()
        if let current = editors[id] { current.window?.makeKeyAndOrderFront(nil); return }
        let show = { [weak self] in
            guard let self else { return }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 530), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Settings"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, cloudSync: cloudSync))
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

    private func restorePinned() {
        for note in store.active where note.pinned { openEditor(note.id) }
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
    let settings = AppSettings()
    lazy var store = NotesStore(settings: settings)
    lazy var cloudSync = CloudSyncController(store: store, settings: settings)
    lazy var coordinator = AppCoordinator(store: store, settings: settings, cloudSync: cloudSync)
    private var hotKeys: HotKeyManager?
    private var shortcutObservation: AnyCancellable?
    private var dockObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var leftSideItem: NSMenuItem?
    private var rightSideItem: NSMenuItem?
    private var bottomSideItem: NSMenuItem?

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
        NSApp.mainMenu = Self.makeMainMenu()
        installHotKeys()
        shortcutObservation = settings.$quickShortcut.dropFirst().sink { [weak self] _ in self?.installHotKeys() }
        dockObservation = settings.$showInDock.dropFirst().sink { show in NSApp.setActivationPolicy(show ? .regular : .accessory) }
        installStatusItem()
        coordinator.start()
    }

    static func activationPolicy(showInDock: Bool, uiTest: Bool) -> NSApplication.ActivationPolicy { showInDock || uiTest ? .regular : .accessory }

    private func installHotKeys() {
        hotKeys = HotKeyManager(
            shortcut: settings.quickShortcut,
            quick: { [weak self] in self?.coordinator.performQuickAction() },
            all: { [weak self] in self?.coordinator.showAllNotes() }
        )
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
    @objc private func statusShowDeck(_ sender: Any?) { coordinator.showDeck() }
    @objc private func statusSideLeft(_ sender: Any?) { settings.side = .left }
    @objc private func statusSideRight(_ sender: Any?) { settings.side = .right }
    @objc private func statusSideBottom(_ sender: Any?) { settings.side = .bottom }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum AppSelfCheck {
    static func run() throws {
        let hasSelectAll = AppDelegate.editCommands.contains { $0.key == "a" && $0.action == #selector(NSText.selectAll(_:)) }
        guard hasSelectAll else { throw SelfCheckFailure("Command-A is not routed to Select All") }
        if NSApp != nil {
            let hasClose = AppDelegate.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items).contains {
                $0.keyEquivalent == "w" && $0.action == #selector(NSWindow.performClose(_:))
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
        guard ChecklistNSTextView.links(in: "Visit https://example.com now").first?.0.absoluteString == "https://example.com" else {
            throw SelfCheckFailure("URLs are not recognized in note text")
        }
        guard ChecklistNSTextView.opensLink(with: []),
              !ChecklistNSTextView.opensLink(with: [.command]),
              !ChecklistNSTextView.opensLink(with: [.option]),
              !ChecklistNSTextView.opensLink(with: [.control]),
              !ChecklistNSTextView.opensLink(with: [.shift]) else {
            throw SelfCheckFailure("Modified clicks do not place the caret inside links")
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
        let editor = ChecklistNSTextView()
        editor.noteFont = .systemFont(ofSize: 21)
        editor.string = "- [ ] First task"
        editor.applyStyle()
        guard (editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent == 18,
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
}
