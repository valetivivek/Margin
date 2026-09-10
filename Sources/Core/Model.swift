import Combine
import Carbon
import CryptoKit
import Foundation
import Security
import SQLite3

enum NoteColor: Int, CaseIterable, Codable {
    case amber, coral, mint, sky, lilac

    var next: Self { Self.allCases[(rawValue + 1) % Self.allCases.count] }
}

enum ScreenSide: String, CaseIterable, Codable { case left, right, bottom }
enum FanMode: String, CaseIterable, Codable { case hover, click }
enum AnimationSpeed: String, CaseIterable, Codable { case fast, normal, slow }
enum AppearanceMode: String, CaseIterable, Codable {
    case system, light, dark
    static func initial(saved: String?) -> Self { Self(rawValue: saved ?? "light") ?? .light }
}
enum InterfaceColor: String, CaseIterable { case clay, olive, slate, plum, graphite }
enum ShortcutAction: String, CaseIterable, Codable { case openTop = "Open top note", newNote = "New note" }

enum KeyboardAction: String, CaseIterable {
    case quick, allNotes, archive, position, hide, settings, close

    var title: String {
        switch self {
        case .quick: "Quick capture"
        case .allNotes: "All Notes"
        case .archive: "Archive"
        case .position: "Change deck position"
        case .hide: "Hide / show deck and notes"
        case .settings: "Open Settings"
        case .close: "Close window"
        }
    }

    var isGlobal: Bool { self != .settings && self != .close }
    var standard: GlobalShortcut {
        let key: (Int, String) = switch self {
        case .quick: (kVK_ANSI_N, "N")
        case .allNotes: (kVK_ANSI_L, "L")
        case .archive: (kVK_ANSI_A, "A")
        case .position: (kVK_ANSI_E, "E")
        case .hide: (kVK_ANSI_H, "H")
        case .settings: (kVK_ANSI_Comma, ",")
        case .close: (kVK_ANSI_W, "W")
        }
        return GlobalShortcut(keyCode: UInt32(key.0), modifiers: UInt32(cmdKey | (isGlobal ? optionKey : 0) | (self == .hide ? controlKey : 0)), key: key.1)
    }
}

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let standard = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), key: "N")

    func matches(_ other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .compactMap { modifiers & UInt32($0.0) == 0 ? nil : $0.1 }.joined() + key
    }
}

struct NotePresentation: Codable, Equatable {
    var colorHex: UInt32?
    var icon: String?
    var richText: Data?
    var richTextBaseSize: Double?
}

enum NoteIcons {
    static let menuBar = ["note.text", "square.stack", "pencil", "checklist", "book", "bookmark"]
    static let all = ["note.text", "square.stack", "pencil", "checklist", "star", "heart", "lightbulb", "book", "bookmark", "briefcase", "house", "flag", "leaf", "bolt", "calendar", "cup.and.saucer"]
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "Untitled note"
    var body = ""
    var color = NoteColor.amber
    var pinned = false
    var createdAt = Date()
    var updatedAt = Date()
    var archivedAt: Date?
    var deletedAt: Date?
    var sortIndex = 0.0
    var pinX: Double?
    var pinY: Double?
    var presentation: NotePresentation?
}

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    @Published var side: ScreenSide { didSet { save("side", side.rawValue) } }
    @Published var deckPosition: Double { didSet { save("deckPosition", deckPosition) } }
    @Published var activationDelay: Double { didSet { save("activationDelay", activationDelay) } }
    @Published var fanMode: FanMode { didSet { save("fanMode", fanMode.rawValue) } }
    @Published var keepOpen: Bool { didSet { save("keepOpen", keepOpen) } }
    @Published var fontName: String { didSet { save("fontName", fontName) } }
    @Published var textSize: Double { didSet { save("textSize", textSize) } }
    @Published var animationSpeed: AnimationSpeed { didSet { save("animationSpeed", animationSpeed.rawValue) } }
    @Published var calendarEnabled: Bool { didSet { save("calendarEnabled", calendarEnabled) } }
    @Published var calendarPosition: Int { didSet { save("calendarPosition", calendarPosition) } }
    @Published var calendarID: String { didSet { save("calendarID", calendarID) } }
    @Published var calendarVisibleIDs: [String] { didSet { save("calendarVisibleIDs", calendarVisibleIDs) } }
    @Published var calendarColor: NoteColor { didSet { save("calendarColor", calendarColor.rawValue) } }
    @Published var cloudSyncEnabled: Bool { didSet { save("cloudSyncEnabled", cloudSyncEnabled) } }
    @Published var cloudSyncBookmark: Data? { didSet { save("cloudSyncBookmark", cloudSyncBookmark) } }
    @Published var menuBarIcon: String { didSet { save("menuBarIcon", menuBarIcon) } }
    @Published var showInDock: Bool { didSet { save("showInDock", showInDock) } }
    @Published var display: String { didSet { save("display", display) } }
    @Published var showOverFullScreen: Bool { didSet { save("showOverFullScreen", showOverFullScreen) } }
    @Published var lockNotes: Bool { didSet { save("lockNotes", lockNotes) } }
    @Published var appearance: AppearanceMode { didSet { save("appearance", appearance.rawValue) } }
    @Published var interfaceColor: InterfaceColor { didSet { save("interfaceColor", interfaceColor.rawValue) } }
    @Published var useDefaultColor: Bool { didSet { save("useDefaultColor", useDefaultColor) } }
    @Published var defaultColorHex: UInt32? { didSet { save("defaultColorHex", defaultColorHex.map { Int($0) }) } }
    @Published var defaultColor: NoteColor { didSet { save("defaultColor", defaultColor.rawValue) } }
    @Published var shortcuts: [String: GlobalShortcut] { didSet { save("shortcuts", try? JSONEncoder().encode(shortcuts)) } }
    @Published var disabledShortcuts: [String] { didSet { save("disabledShortcuts", disabledShortcuts) } }
    @Published var shareNotes: Bool { didSet { save("shareNotes", shareNotes) } }
    @Published var markdownEnabled: Bool { didSet { save("markdownEnabled", markdownEnabled) } }
    @Published var markdownPreviewDelay: Double { didSet { save("markdownPreviewDelay", markdownPreviewDelay) } }
    @Published var shortcutError: String?
    @Published var shortcutAction: ShortcutAction { didSet { save("shortcutAction", shortcutAction.rawValue) } }

    var animationScale: Double {
        switch animationSpeed { case .fast: 0.72; case .normal: 1.0; case .slow: 1.35 }
    }
    var animationDuration: Double { 0.20 * animationScale }
    var fanDuration: Double { 0.50 * animationScale }
    var cardDuration: Double { 0.38 * animationScale }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        side = ScreenSide(rawValue: defaults.string(forKey: "side") ?? "right") ?? .right
        deckPosition = min(1, max(0, defaults.object(forKey: "deckPosition") as? Double ?? 0.5))
        activationDelay = min(1, max(0, defaults.object(forKey: "activationDelay") as? Double ?? 0.05))
        fanMode = FanMode(rawValue: defaults.string(forKey: "fanMode") ?? "hover") ?? .hover
        keepOpen = defaults.bool(forKey: "keepOpen")
        fontName = defaults.string(forKey: "fontName") ?? "Helvetica"
        textSize = defaults.object(forKey: "textSize") as? Double ?? 21
        animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: "animationSpeed") ?? "normal") ?? .normal
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        calendarPosition = defaults.object(forKey: "calendarPosition") as? Int
            ?? ((defaults.object(forKey: "calendarFirst") as? Bool ?? true) ? 0 : Int.max)
        let savedCalendarID = defaults.string(forKey: "calendarID") ?? ""
        calendarID = savedCalendarID
        calendarVisibleIDs = defaults.stringArray(forKey: "calendarVisibleIDs")
            ?? (savedCalendarID.isEmpty ? [] : [savedCalendarID])
        calendarColor = (defaults.object(forKey: "calendarColor") as? Int).flatMap(NoteColor.init(rawValue:)) ?? .sky
        cloudSyncEnabled = false // Cloud Sync is unavailable in this build.
        cloudSyncBookmark = defaults.data(forKey: "cloudSyncBookmark")
        menuBarIcon = defaults.string(forKey: "menuBarIcon").flatMap { NoteIcons.menuBar.contains($0) ? $0 : nil } ?? "note.text"
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? false
        display = defaults.string(forKey: "display") ?? "main"
        showOverFullScreen = defaults.object(forKey: "showOverFullScreen") as? Bool ?? true
        lockNotes = defaults.bool(forKey: "lockNotes")
        appearance = AppearanceMode.initial(saved: defaults.string(forKey: "appearance"))
        interfaceColor = InterfaceColor(rawValue: defaults.string(forKey: "interfaceColor") ?? "") ?? .clay
        useDefaultColor = defaults.bool(forKey: "useDefaultColor")
        defaultColorHex = (defaults.object(forKey: "defaultColorHex") as? NSNumber).flatMap { (0...0xFFFFFF).contains($0.int64Value) ? UInt32($0.int64Value) : nil }
        defaultColor = NoteColor(rawValue: defaults.integer(forKey: "defaultColor")) ?? .amber
        shareNotes = defaults.object(forKey: "shareNotes") as? Bool ?? true
        markdownEnabled = defaults.object(forKey: "markdownEnabled") as? Bool ?? false
        markdownPreviewDelay = min(60, max(1, defaults.object(forKey: "markdownPreviewDelay") as? Double ?? 5))
        shortcuts = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: GlobalShortcut].self, from: $0) } ?? [:]
        disabledShortcuts = defaults.stringArray(forKey: "disabledShortcuts") ?? []
        shortcutAction = ShortcutAction(rawValue: defaults.string(forKey: "shortcutAction") ?? "") ?? .newNote
        if shortcuts.isEmpty, let legacy = defaults.data(forKey: "quickShortcut").flatMap({ try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }),
           !KeyboardAction.allCases.filter({ $0 != .quick }).contains(where: { $0.standard.matches(legacy) }) {
            shortcuts[KeyboardAction.quick.rawValue] = legacy
        }
    }

    func shortcutEnabled(_ action: KeyboardAction) -> Bool { !disabledShortcuts.contains(action.rawValue) }

    func setShortcutEnabled(_ enabled: Bool, for action: KeyboardAction) {
        if enabled { disabledShortcuts.removeAll { $0 == action.rawValue } }
        else if shortcutEnabled(action) { disabledShortcuts.append(action.rawValue) }
    }

    func shortcut(for action: KeyboardAction) -> GlobalShortcut { shortcuts[action.rawValue] ?? action.standard }

    func setShortcut(_ shortcut: GlobalShortcut, for action: KeyboardAction) -> Bool {
        if let conflict = KeyboardAction.allCases.first(where: { $0 != action && self.shortcut(for: $0).matches(shortcut) }) {
            shortcutError = "That shortcut is already used by \(conflict.title)."
            return false
        }
        // Keep standard editing and Quit available while a note is focused.
        if shortcut.modifiers == UInt32(cmdKey), [kVK_ANSI_Q, kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_F, kVK_ANSI_Period, kVK_Delete].contains(Int(shortcut.keyCode)) {
            shortcutError = "That shortcut is reserved for editing or quitting Margin."
            return false
        }
        shortcutError = nil
        shortcuts[action.rawValue] = shortcut
        return true
    }

    var lastNotePosition: (x: Double, y: Double)? {
        guard defaults.object(forKey: "lastNoteX") != nil, defaults.object(forKey: "lastNoteY") != nil else { return nil }
        return (defaults.double(forKey: "lastNoteX"), defaults.double(forKey: "lastNoteY"))
    }

    var lastOpenNoteID: UUID? {
        get { defaults.string(forKey: "lastOpenNoteID").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "lastOpenNoteID") }
    }

    func rememberNotePosition(x: Double, y: Double) {
        defaults.set(x, forKey: "lastNoteX"); defaults.set(y, forKey: "lastNoteY")
    }

    private func save(_ key: String, _ value: Any?) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        onChange?()
    }
}

private enum StoreError: LocalizedError {
    case sqlite(String), keychain(OSStatus), corruptNote
    var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        case .keychain(let status): "Keychain error \(status)"
        case .corruptNote: "A note could not be decrypted."
        }
    }
}

private final class CryptoBox {
    private let key: SymmetricKey
    init(service: String = "app.margin.local-key", keyData: Data? = nil) throws {
        if let keyData { key = SymmetricKey(data: keyData); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "note-body-key",
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            key = SymmetricKey(data: data)
            return
        }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }
        var data = Data(count: 32)
        let randomStatus = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw StoreError.keychain(randomStatus) }
        var add = query
        add.removeValue(forKey: kSecReturnData as String)
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        key = SymmetricKey(data: data)
    }

    func encrypt(_ string: String) throws -> Data {
        guard let combined = try AES.GCM.seal(Data(string.utf8), using: key).combined else { throw StoreError.corruptNote }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        guard let value = String(data: plain, encoding: .utf8) else { throw StoreError.corruptNote }
        return value
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NoteDatabase {
    private var db: OpaquePointer?
    private let crypto: CryptoBox

    init(directory: URL? = nil, keyService: String = "app.margin.local-key", keyData: Data? = nil) throws {
        crypto = try CryptoBox(service: keyService, keyData: keyData)
        let folder = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Margin", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("notes.sqlite3")
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.sqlite("Could not open the note store.")
        }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try execute("""
            CREATE TABLE IF NOT EXISTS note (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, body BLOB NOT NULL,
              color INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0,
              created REAL NOT NULL, updated REAL NOT NULL, archived REAL,
              deleted REAL, sort_index REAL NOT NULL, pin_x REAL, pin_y REAL
            );
            """)
        let columns = try prepare("PRAGMA table_info(note)")
        var hasPresentation = false
        while sqlite3_step(columns) == SQLITE_ROW {
            if String(cString: sqlite3_column_text(columns, 1)) == "presentation" { hasPresentation = true }
        }
        sqlite3_finalize(columns)
        if !hasPresentation { try execute("ALTER TABLE note ADD COLUMN presentation BLOB") }
    }

    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(error)
            throw StoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    func load(includeDeleted: Bool = false) throws -> [Note] {
        let condition = includeDeleted ? "" : " WHERE deleted IS NULL"
        let statement = try prepare("SELECT id,title,body,color,pinned,created,updated,archived,deleted,sort_index,pin_x,pin_y,presentation FROM note\(condition) ORDER BY sort_index")
        defer { sqlite3_finalize(statement) }
        var result: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: idText)) else { continue }
            let title = String(cString: sqlite3_column_text(statement, 1))
            let bytes = sqlite3_column_blob(statement, 2)
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard let bytes else { continue }
            let body = try crypto.decrypt(Data(bytes: bytes, count: count))
            var presentation: NotePresentation?
            if let bytes = sqlite3_column_blob(statement, 12) {
                let encrypted = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 12)))
                presentation = try JSONDecoder().decode(NotePresentation.self, from: Data(crypto.decrypt(encrypted).utf8))
            }
            result.append(Note(
                id: id,
                title: title,
                body: body,
                color: NoteColor(rawValue: Int(sqlite3_column_int(statement, 3))) ?? .amber,
                pinned: sqlite3_column_int(statement, 4) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                archivedAt: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                deletedAt: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                sortIndex: sqlite3_column_double(statement, 9),
                pinX: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 10),
                pinY: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 11),
                presentation: presentation
            ))
        }
        return result
    }

    func save(_ note: Note) throws {
        let sql = """
          INSERT INTO note(id,title,body,color,pinned,created,updated,archived,deleted,sort_index,pin_x,pin_y,presentation)
          VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
          ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,color=excluded.color,
          pinned=excluded.pinned,updated=excluded.updated,archived=excluded.archived,deleted=excluded.deleted,
          sort_index=excluded.sort_index,pin_x=excluded.pin_x,pin_y=excluded.pin_y,presentation=excluded.presentation
          """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let encrypted = try crypto.encrypt(note.body)
        sqlite3_bind_text(statement, 1, note.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, note.title, -1, sqliteTransient)
        _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), sqliteTransient) }
        sqlite3_bind_int(statement, 4, Int32(note.color.rawValue))
        sqlite3_bind_int(statement, 5, note.pinned ? 1 : 0)
        sqlite3_bind_double(statement, 6, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, note.updatedAt.timeIntervalSince1970)
        bind(note.archivedAt, to: 8, in: statement)
        bind(note.deletedAt, to: 9, in: statement)
        sqlite3_bind_double(statement, 10, note.sortIndex)
        bind(note.pinX, to: 11, in: statement)
        bind(note.pinY, to: 12, in: statement)
        if let presentation = note.presentation {
            let json = try JSONEncoder().encode(presentation)
            let encrypted = try crypto.encrypt(String(decoding: json, as: UTF8.self))
            _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 13, $0.baseAddress, Int32($0.count), sqliteTransient) }
        } else { sqlite3_bind_null(statement, 13) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    private func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer?) {
        if let value { sqlite3_bind_double(statement, index, value.timeIntervalSince1970) } else { sqlite3_bind_null(statement, index) }
    }
    private func bind(_ value: Double?, to index: Int32, in statement: OpaquePointer?) {
        if let value { sqlite3_bind_double(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }
}

struct StickyArchive: Codable {
    var version = 1
    var notes: [Note]
}

enum NoteSaveState { case saved, pending, failed }

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var undoNote: Note?
    @Published var errorMessage: String?

    let settings: AppSettings
    private let database: NoteDatabase
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var drafts: [UUID: Note] = [:]
    private var failedSaves: Set<UUID> = []
    private var deletedRecords: [UUID: Note] = [:]

    init(settings: AppSettings, database: NoteDatabase? = nil) {
        self.settings = settings
        do {
            let uiTest = CommandLine.arguments.contains("--ui-test")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hmn-ui-test-store-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            self.database = try database ?? (uiTest ? NoteDatabase(directory: folder, keyData: Data(repeating: 5, count: 32)) : NoteDatabase())
            let records = try self.database.load(includeDeleted: true)
            notes = records.filter { $0.deletedAt == nil }
            deletedRecords = Dictionary(uniqueKeysWithValues: records.compactMap { note in note.deletedAt == nil ? nil : (note.id, note) })
            if uiTest && notes.isEmpty {
                let active = Note(title: "Office", body: "one two three\n- [ ] ship the release", color: .sky, sortIndex: 0)
                var archived = Note(title: "Getting started", body: "Archived test note", color: .amber, sortIndex: 1)
                archived.archivedAt = Date().addingTimeInterval(-7_200)
                try self.database.save(active); try self.database.save(archived); notes = [active, archived]
            }
        } catch {
            fatalError("Margin cannot open its note store: \(error.localizedDescription)")
        }
    }

    var active: [Note] { notes.filter { $0.archivedAt == nil }.sorted { $0.sortIndex < $1.sortIndex } }
    var archived: [Note] { notes.filter { $0.archivedAt != nil }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) } }

    var nextNoteColor: NoteColor {
        settings.useDefaultColor
            ? settings.defaultColor
            : notes.max { $0.createdAt < $1.createdAt }?.color.next ?? .amber
    }

    @discardableResult func create() -> Note {
        let next = (notes.map(\Note.sortIndex).max() ?? -1) + 1
        let note = Note(color: nextNoteColor, sortIndex: next, presentation: settings.useDefaultColor ? settings.defaultColorHex.map { NotePresentation(colorHex: $0) } : nil)
        notes.append(note)
        persist(note)
        return note
    }

    @discardableResult func seedWelcomeIfNeeded() -> Note {
        guard notes.isEmpty else { return notes[0] }
        var note = create()
        note.title = "Getting started"
        note.body = "Hover the right edge of the screen to open your deck.\n\n- Click a card to open it\n- Drag cards up / down to arrange them\n- Pin a note to keep it on your desktop\n- ⌥⌘N makes a new note, ⌥⌘L lists them all\n\nReplace this with your first note."
        persist(note)
        return note
    }

    func note(_ id: UUID) -> Note? { drafts[id] ?? notes.first { $0.id == id } }

    func saveState(_ id: UUID) -> NoteSaveState {
        if failedSaves.contains(id) { return .failed }
        return drafts[id] == nil ? .saved : .pending
    }

    // Mutate the latest draft, never a possibly stale copy held by a caller.
    @discardableResult
    func edit(_ id: UUID, immediate: Bool = false, _ change: (inout Note) -> Void) -> Note? {
        guard var value = note(id) else { return nil }
        let previous = value
        change(&value)
        guard value != previous else {
            if immediate { flush(id) }
            return value
        }
        value.updatedAt = Date()
        drafts[id] = value
        pending.removeValue(forKey: id)?.cancel()
        if immediate { flush(id) }
        else {
            let work = DispatchWorkItem { [weak self] in self?.flush(id) }
            pending[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        return value
    }

    @discardableResult
    func flush(_ id: UUID) -> Bool {
        pending.removeValue(forKey: id)?.cancel()
        guard let draft = drafts[id], let index = notes.firstIndex(where: { $0.id == id }) else { return true }
        let saved = write(draft)
        if saved { drafts[id] = nil }
        notes[index] = draft
        return saved
    }

    @discardableResult
    func flushAll() -> Bool {
        var saved = true
        for id in Array(drafts.keys) { if !flush(id) { saved = false } }
        return saved
    }

    @discardableResult
    func archive(_ id: UUID) -> Bool {
        guard edit(id, { $0.archivedAt = Date(); $0.pinned = false }) != nil else { return false }
        return flush(id)
    }

    @discardableResult
    func restore(_ id: UUID) -> Bool {
        let nextIndex = (active.map(\Note.sortIndex).max() ?? -1) + 1
        guard edit(id, { $0.archivedAt = nil; $0.sortIndex = nextIndex }) != nil else { return false }
        return flush(id)
    }

    func duplicate(_ id: UUID) -> Note? {
        guard var copy = note(id) else { return nil }
        copy.id = UUID(); copy.title += " copy"; copy.createdAt = Date(); copy.updatedAt = Date()
        copy.archivedAt = nil; copy.pinned = false; copy.sortIndex = (active.map(\Note.sortIndex).max() ?? -1) + 1
        notes.append(copy); persist(copy)
        return copy
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }), let note = note(id) else { return false }
        var tombstone = note; tombstone.updatedAt = Date(); tombstone.deletedAt = tombstone.updatedAt
        guard write(tombstone) else { return false }
        pending.removeValue(forKey: id)?.cancel()
        drafts[id] = nil
        notes.remove(at: index)
        deletedRecords[id] = tombstone
        undoNote = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.undoNote?.id == id { self?.undoNote = nil }
        }
        return true
    }

    func undoDelete() {
        guard var note = undoNote else { return }
        note.deletedAt = nil; note.updatedAt = Date()
        deletedRecords[note.id] = nil
        notes.append(note); undoNote = nil; persist(note)
    }

    func recordsForSync() -> [Note] {
        notes.map { drafts[$0.id] ?? $0 } + Array(deletedRecords.values)
    }

    func mergeSynced(_ remote: Note) {
        let local = note(remote.id) ?? deletedRecords[remote.id]
        let remoteDate = remote.deletedAt ?? remote.updatedAt
        let localDate = local.map { $0.deletedAt ?? $0.updatedAt } ?? .distantPast
        guard remoteDate > localDate else { return }
        pending[remote.id]?.cancel(); pending[remote.id] = nil; drafts[remote.id] = nil
        var persisted = remote
        if remote.deletedAt != nil {
            notes.removeAll { $0.id == remote.id }
            deletedRecords[remote.id] = remote
        } else if let index = notes.firstIndex(where: { $0.id == remote.id }) {
            var value = remote
            if remote.archivedAt == nil {
                value.pinned = notes[index].pinned; value.pinX = notes[index].pinX; value.pinY = notes[index].pinY
            } else {
                value.pinned = false; value.pinX = nil; value.pinY = nil
            }
            persisted = value
            notes[index] = value; deletedRecords[remote.id] = nil
        } else {
            var value = remote
            value.pinned = false; value.pinX = nil; value.pinY = nil
            persisted = value
            notes.append(value); deletedRecords[remote.id] = nil
        }
        do { try database.save(persisted) } catch { errorMessage = error.localizedDescription }
    }

    func move(_ source: UUID, before target: UUID) {
        var items = active
        guard let from = items.firstIndex(where: { $0.id == source }), let to = items.firstIndex(where: { $0.id == target }) else { return }
        let moved = items.remove(at: from); items.insert(moved, at: to)
        for (index, note) in items.enumerated() { edit(note.id, immediate: true) { $0.sortIndex = Double(index) } }
    }

    func move(_ source: UUID, by step: Int) {
        let items = active
        guard let from = items.firstIndex(where: { $0.id == source }) else { return }
        let to = min(items.count - 1, max(0, from + step))
        guard from != to else { return }
        move(source, before: items[to].id)
    }

    func search(_ query: String, archivedOnly: Bool? = nil) -> [Note] {
        let source = notes.filter { archivedOnly == nil || ($0.archivedAt != nil) == archivedOnly! }
        guard !query.isEmpty else { return source }
        return source.filter { ($0.title + "\n" + $0.body).localizedCaseInsensitiveContains(query) }
    }

    func importFiles(_ urls: [URL]) {
        do {
            for url in urls {
                if url.pathExtension.lowercased() == "stickies" {
                    let archive = try JSONDecoder.hmn.decode(StickyArchive.self, from: Data(contentsOf: url))
                    for var note in archive.notes { note.id = UUID(); note.sortIndex = (notes.map(\Note.sortIndex).max() ?? -1) + 1; notes.append(note); persist(note) }
                } else {
                    let body = try String(contentsOf: url, encoding: .utf8)
                    let note = create()
                    edit(note.id, immediate: true) { $0.title = url.deletingPathExtension().lastPathComponent; $0.body = body }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func archiveData(_ values: [Note]) throws -> Data { try JSONEncoder.hmn.encode(StickyArchive(notes: values)) }

    private func persist(_ note: Note) {
        drafts[note.id] = note
        flush(note.id)
    }

    private func write(_ note: Note) -> Bool {
        do {
            try database.save(note)
            failedSaves.remove(note.id)
            return true
        } catch {
            failedSaves.insert(note.id)
            errorMessage = error.localizedDescription
            return false
        }
    }
}

extension JSONEncoder {
    static var hmn: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; value.dateEncodingStrategy = .millisecondsSince1970; return value }
}
extension JSONDecoder {
    static var hmn: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .millisecondsSince1970; return value }
}

enum SelfCheck {
    static func run() throws {
        try checkSettingsPersistence()
        guard AppearanceMode.initial(saved: nil) == .light,
              AppearanceMode.initial(saved: "system") == .system,
              AppearanceMode.initial(saved: "dark") == .dark else {
            throw SelfCheckFailure("Light is not the default appearance")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("margin-self-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try NoteDatabase(directory: folder, keyService: "app.margin.self-check", keyData: Data(repeating: 7, count: 32))
        var note = Note(title: "Round trip", body: "secret checklist\n- [ ] works", color: .mint)
        try db.save(note)
        let loaded = try db.load()
        precondition(loaded.count == 1 && loaded[0].body == note.body && loaded[0].color == .mint)
        note.presentation = NotePresentation(colorHex: 0x123456, icon: "star", richText: Data("rich body".utf8))
        try db.save(note)
        guard try db.load()[0].presentation == note.presentation else { throw SelfCheckFailure("Note colors, icons or formatting do not persist") }
        note.body = "changed"; try db.save(note)
        let changed = try db.load()
        precondition(changed[0].body == "changed")
        let archive = try JSONEncoder.hmn.encode(StickyArchive(notes: changed))
        let imported = try JSONDecoder.hmn.decode(StickyArchive.self, from: archive)
        precondition(imported.notes[0].title == "Round trip")

        note.deletedAt = Date()
        try db.save(note)
        let remaining = try db.load()
        precondition(remaining.isEmpty)
        let includingDeleted = try db.load(includeDeleted: true)
        precondition(includingDeleted.first?.deletedAt != nil)

        let syncFolder = FileManager.default.temporaryDirectory.appendingPathComponent("margin-sync-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: syncFolder) }
        let syncBookmark = try CloudSyncBookmark.make(for: syncFolder)
        guard try CloudSyncBookmark.resolve(syncBookmark).url.standardizedFileURL == syncFolder.standardizedFileURL else {
            throw SelfCheckFailure("Cloud Sync does not remember its selected folder")
        }
        var synced = Note(title: "Cloud note", body: "Local body", color: .sky)
        synced.updatedAt = Date().addingTimeInterval(-60)
        let initialSync = try CloudSyncEngine.sync(local: [synced], folder: syncFolder)
        let markdownURL = try FileManager.default.contentsOfDirectory(at: syncFolder, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "md" }
        guard initialSync.changedCount == 1, let markdownURL,
              try String(contentsOf: markdownURL, encoding: .utf8) == "# Cloud note\n\nLocal body" else {
            throw SelfCheckFailure("Cloud Sync does not write readable note files")
        }
        try "# Edited in iCloud\n\nRemote body".write(to: markdownURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: markdownURL.path)
        let incoming = try CloudSyncEngine.sync(local: [synced], folder: syncFolder).incoming.first
        guard incoming?.title == "Edited in iCloud", incoming?.body == "Remote body" else {
            throw SelfCheckFailure("Cloud Sync does not merge newer Markdown edits")
        }
        guard var tombstone = incoming else { throw SelfCheckFailure("Cloud Sync did not return the edited note") }
        tombstone.updatedAt = Date().addingTimeInterval(10); tombstone.deletedAt = tombstone.updatedAt
        _ = try CloudSyncEngine.sync(local: [tombstone], folder: syncFolder)
        guard !FileManager.default.fileExists(atPath: markdownURL.path),
              try CloudSyncEngine.sync(local: [], folder: syncFolder).incoming.first?.deletedAt != nil else {
            throw SelfCheckFailure("Cloud Sync does not propagate note deletions")
        }

        let editFolder = FileManager.default.temporaryDirectory.appendingPathComponent("margin-edit-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: editFolder) }
        let editDB = try NoteDatabase(directory: editFolder, keyService: "app.margin.edit-check", keyData: Data(repeating: 9, count: 32))
        let suite = "margin-check-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storeSettings = AppSettings(defaults: defaults)
        guard !storeSettings.markdownEnabled, storeSettings.markdownPreviewDelay == 5, storeSettings.activationDelay == 0.05, storeSettings.deckPosition == 0.5, storeSettings.display == "main", storeSettings.fontName == "Helvetica", !storeSettings.showInDock, storeSettings.showOverFullScreen else {
            throw SelfCheckFailure("New deck defaults are incorrect")
        }
        storeSettings.showOverFullScreen = false
        guard !AppSettings(defaults: defaults).showOverFullScreen else {
            throw SelfCheckFailure("Saved fullscreen opt-out is overwritten by the default")
        }
        guard !storeSettings.setShortcut(KeyboardAction.archive.standard, for: .allNotes),
              storeSettings.setShortcut(GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey), key: "K"), for: .allNotes),
              AppSettings(defaults: defaults).shortcut(for: .allNotes).key == "K" else {
            throw SelfCheckFailure("Shortcut conflicts or persistence are broken")
        }
        storeSettings.menuBarIcon = "pencil"
        guard AppSettings(defaults: defaults).menuBarIcon == "pencil" else { throw SelfCheckFailure("Menu bar icon is not remembered") }
        storeSettings.calendarColor = .lilac
        guard AppSettings(defaults: defaults).calendarColor == .lilac else { throw SelfCheckFailure("Calendar color is not remembered") }
        storeSettings.calendarID = "primary"; storeSettings.calendarVisibleIDs = ["work", "family"]
        let calendarSettings = AppSettings(defaults: defaults)
        guard calendarSettings.calendarID == "primary", calendarSettings.calendarVisibleIDs == ["work", "family"] else {
            throw SelfCheckFailure("Calendar selections are not remembered")
        }
        storeSettings.markdownPreviewDelay = 12; storeSettings.activationDelay = 0.7; storeSettings.deckPosition = 0.25; storeSettings.display = "external-display"
        let restored = AppSettings(defaults: defaults)
        guard restored.markdownPreviewDelay == 12, restored.activationDelay == 0.7, restored.deckPosition == 0.25, restored.display == "external-display" else {
            throw SelfCheckFailure("Deck preferences are not persisted")
        }
        storeSettings.setShortcutEnabled(false, for: .hide)
        storeSettings.setShortcutEnabled(false, for: .settings)
        let disabledSettings = AppSettings(defaults: defaults)
        guard !disabledSettings.shortcutEnabled(.hide), !disabledSettings.shortcutEnabled(.settings), disabledSettings.shortcutEnabled(.close) else {
            throw SelfCheckFailure("Individual shortcut toggles do not persist independently")
        }
        let menu = AppDelegate.makeMainMenu(settings: disabledSettings)
        guard menu.items.compactMap(\.submenu).flatMap(\.items).first(where: { $0.title == "Settings…" })?.keyEquivalent == "" else {
            throw SelfCheckFailure("Disabled window shortcut still has a menu key equivalent")
        }
        storeSettings.setShortcutEnabled(true, for: .hide)
        storeSettings.setShortcutEnabled(true, for: .settings)
        storeSettings.shortcuts = [:]
        let savedDefault = storeSettings.defaultColor
        let savedUseDefault = storeSettings.useDefaultColor
        let savedLastOpenNoteID = storeSettings.lastOpenNoteID
        defer {
            storeSettings.defaultColor = savedDefault; storeSettings.useDefaultColor = savedUseDefault
            storeSettings.lastOpenNoteID = savedLastOpenNoteID
        }
        let rememberedNoteID = UUID()
        storeSettings.lastOpenNoteID = rememberedNoteID
        guard AppSettings(defaults: defaults).lastOpenNoteID == rememberedNoteID else {
            throw SelfCheckFailure("The last-opened note is not remembered")
        }
        storeSettings.useDefaultColor = true
        storeSettings.defaultColor = .lilac
        let store = NotesStore(settings: storeSettings, database: editDB)
        let edited = store.create()
        guard edited.color == .lilac else { throw SelfCheckFailure("New notes ignore the selected default color") }
        guard store.create().color == .lilac else { throw SelfCheckFailure("Default color mode does not stay fixed") }
        storeSettings.defaultColorHex = 0x1256AB
        let customNote = store.create()
        guard customNote.presentation?.colorHex == 0x1256AB, AppSettings(defaults: defaults).defaultColorHex == 0x1256AB else {
            throw SelfCheckFailure("The custom color in Settings does not persist or apply to new notes")
        }
        storeSettings.defaultColorHex = nil
        storeSettings.useDefaultColor = false
        guard store.create().color == .amber, store.create().color == .coral else {
            throw SelfCheckFailure("Consecutive new notes do not rotate colors")
        }
        let originalOrder = store.active.map(\.id)
        let reorderedID = originalOrder[0]
        store.move(reorderedID, by: 1)
        guard store.active[1].id == reorderedID else { throw SelfCheckFailure("Wheel reordering does not move down a slot") }
        store.move(reorderedID, by: -1)
        store.move(reorderedID, by: -1)
        guard store.active.map(\.id) == originalOrder else { throw SelfCheckFailure("Wheel reordering does not clamp at the first slot") }
        store.move(reorderedID, by: originalOrder.count)
        store.move(reorderedID, by: 1)
        guard store.active.last?.id == reorderedID else { throw SelfCheckFailure("Wheel reordering does not clamp at the final slot") }
        store.move(reorderedID, by: -originalOrder.count)
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        for index in 0..<100 { store.edit(edited.id) { $0.body = "keystroke \(index)" } }
        withExtendedLifetime(observation) {}
        guard publications <= 1 else { throw SelfCheckFailure("Editing published the entire note list \(publications) times") }
        store.flush(edited.id)
        guard store.active.first(where: { $0.id == edited.id })?.body == "keystroke 99",
              try editDB.load().first(where: { $0.id == edited.id })?.body == "keystroke 99" else {
            throw SelfCheckFailure("Closing an editor does not flush its pending draft")
        }
        store.edit(edited.id) { $0.body = "saved before update" }
        store.flushAll()
        guard try editDB.load().first(where: { $0.id == edited.id })?.body == "saved before update" else {
            throw SelfCheckFailure("Quitting for an update loses pending note edits")
        }
        store.edit(edited.id) { $0.body = "pending text"; $0.presentation = NotePresentation(richText: Data([1, 2, 3])) }
        store.edit(edited.id) { $0.pinned = true; $0.pinX = 42 }
        let editTime = store.note(edited.id)!.updatedAt
        guard store.flush(edited.id), store.note(edited.id)?.updatedAt == editTime,
              store.note(edited.id)?.body == "pending text",
              store.note(edited.id)?.presentation?.richText == Data([1, 2, 3]) else {
            throw SelfCheckFailure("Metadata edits overwrite pending text or formatting")
        }
        var failureDB: OpaquePointer?
        guard sqlite3_open(editFolder.appendingPathComponent("notes.sqlite3").path, &failureDB) == SQLITE_OK else {
            throw SelfCheckFailure("Cannot open failure-check database")
        }
        defer { sqlite3_close(failureDB) }
        guard sqlite3_exec(failureDB, "CREATE TRIGGER reject_save BEFORE INSERT ON note BEGIN SELECT RAISE(ABORT, 'test failure'); END", nil, nil, nil) == SQLITE_OK else {
            throw SelfCheckFailure("Cannot inject save failure")
        }
        store.edit(edited.id) { $0.body = "retry this draft" }
        guard !store.flushAll(), store.saveState(edited.id) == .failed,
              store.note(edited.id)?.body == "retry this draft",
              try editDB.load().first(where: { $0.id == edited.id })?.body == "pending text" else {
            throw SelfCheckFailure("Failed save discards the draft or reports success")
        }
        guard sqlite3_exec(failureDB, "DROP TRIGGER reject_save", nil, nil, nil) == SQLITE_OK,
              store.flushAll(), store.saveState(edited.id) == .saved,
              try editDB.load().first(where: { $0.id == edited.id })?.body == "retry this draft" else {
            throw SelfCheckFailure("Failed draft cannot be retried")
        }
        store.errorMessage = nil
        store.edit(edited.id) { $0.body = "archive pending draft" }
        guard store.archive(edited.id), store.restore(edited.id), store.note(edited.id)?.body == "archive pending draft" else {
            throw SelfCheckFailure("Archive loses pending edits")
        }
        store.edit(edited.id) { $0.body = "delete pending draft" }
        guard store.delete(edited.id), store.flush(edited.id), store.note(edited.id) == nil else {
            throw SelfCheckFailure("A pending save resurrects a deleted note")
        }
        store.undoDelete()
        guard store.note(edited.id)?.body == "delete pending draft" else { throw SelfCheckFailure("Undo loses the latest draft") }
        try AppSelfCheck.checkDeckHover(store: store, settings: storeSettings)
        print("Margin self-check passed")
    }

    private static func checkSettingsPersistence() throws {
        let suite = "margin-preference-check-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey), key: "K")
        let noteID = UUID()
        let saved: [String: Any] = [
            "side": "left", "deckPosition": 0.3, "activationDelay": 0.65, "fanMode": "click", "keepOpen": true,
            "fontName": "American Typewriter", "textSize": 19.0, "animationSpeed": "slow",
            "cloudSyncEnabled": true, "cloudSyncBookmark": Data([1, 2, 3]), "showInDock": true,
            "display": "disconnected-display", "showOverFullScreen": true, "lockNotes": true, "appearance": "system",
            "useDefaultColor": true, "defaultColor": NoteColor.lilac.rawValue,
            "shortcuts": try JSONEncoder().encode(["quick": shortcut]), "disabledShortcuts": ["hide", "settings"],
            "shareNotes": false, "markdownEnabled": false, "markdownPreviewDelay": 17.0, "shortcutAction": "Open top note",
            "lastNoteX": 101.0, "lastNoteY": 202.0, "lastOpenNoteID": noteID.uuidString,
            "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false
        ]
        defaults.setPersistentDomain(saved, forName: suite)
        let restored = AppSettings(defaults: defaults)
        guard restored.side == .left, restored.deckPosition == 0.3, restored.activationDelay == 0.65,
              restored.fanMode == .click, restored.keepOpen, restored.fontName == "American Typewriter", restored.textSize == 19,
              restored.animationSpeed == .slow, !restored.cloudSyncEnabled, restored.cloudSyncBookmark == Data([1, 2, 3]),
              restored.showInDock, restored.display == "disconnected-display", restored.showOverFullScreen, restored.lockNotes,
              restored.appearance == .system, restored.interfaceColor == .clay, restored.useDefaultColor, restored.defaultColor == .lilac,
              restored.shortcut(for: .quick) == shortcut, restored.disabledShortcuts == ["hide", "settings"],
              !restored.shareNotes, !restored.markdownEnabled, restored.markdownPreviewDelay == 17, restored.shortcutAction == .openTop,
              restored.lastNotePosition?.x == 101, restored.lastNotePosition?.y == 202, restored.lastOpenNoteID == noteID,
              NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: saved) else {
            throw SelfCheckFailure("Loading settings resets an existing preference")
        }
        restored.interfaceColor = .slate
        restored.appearance = .dark
        var expected = saved; expected["interfaceColor"] = "slate"; expected["appearance"] = "dark"
        let reopened = AppSettings(defaults: defaults)
        guard reopened.interfaceColor == .slate, reopened.appearance == .dark,
              NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: expected) else {
            throw SelfCheckFailure("Appearance changes overwrite unrelated settings or fail to persist")
        }
    }
}

struct SelfCheckFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
