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
    static func initial(saved: String?, lightDefaultApplied: Bool) -> Self {
        saved == "system" && !lightDefaultApplied ? .light : Self(rawValue: saved ?? "light") ?? .light
    }
}
enum ShortcutAction: String, CaseIterable, Codable { case openTop = "Open top note", newNote = "New note" }

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let standard = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), key: "N")

    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .compactMap { modifiers & UInt32($0.0) == 0 ? nil : $0.1 }.joined() + key
    }
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
}

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var side: ScreenSide { didSet { save("side", side.rawValue) } }
    @Published var fanMode: FanMode { didSet { save("fanMode", fanMode.rawValue) } }
    @Published var keepOpen: Bool { didSet { save("keepOpen", keepOpen) } }
    @Published var fontName: String { didSet { save("fontName", fontName) } }
    @Published var textSize: Double { didSet { save("textSize", textSize) } }
    @Published var animationSpeed: AnimationSpeed { didSet { save("animationSpeed", animationSpeed.rawValue) } }
    @Published var cloudSyncEnabled: Bool { didSet { save("cloudSyncEnabled", cloudSyncEnabled) } }
    @Published var cloudSyncBookmark: Data? { didSet { save("cloudSyncBookmark", cloudSyncBookmark) } }
    @Published var showInDock: Bool { didSet { save("showInDock", showInDock) } }
    @Published var showOnAllScreens: Bool { didSet { save("showOnAllScreens", showOnAllScreens) } }
    @Published var showOverFullScreen: Bool { didSet { save("showOverFullScreen", showOverFullScreen) } }
    @Published var lockNotes: Bool { didSet { save("lockNotes", lockNotes) } }
    @Published var appearance: AppearanceMode { didSet { save("appearance", appearance.rawValue) } }
    @Published var useDefaultColor: Bool { didSet { save("useDefaultColor", useDefaultColor) } }
    @Published var defaultColor: NoteColor { didSet { save("defaultColor", defaultColor.rawValue) } }
    @Published var quickShortcut: GlobalShortcut { didSet { save("quickShortcut", try? JSONEncoder().encode(quickShortcut)) } }
    @Published var shortcutAction: ShortcutAction { didSet { save("shortcutAction", shortcutAction.rawValue) } }

    var animationScale: Double {
        switch animationSpeed { case .fast: 0.72; case .normal: 1.0; case .slow: 1.35 }
    }
    var animationDuration: Double { 0.20 * animationScale }
    var fanDuration: Double { 0.50 * animationScale }
    var cardDuration: Double { 0.38 * animationScale }

    init() {
        side = ScreenSide(rawValue: defaults.string(forKey: "side") ?? "right") ?? .right
        fanMode = FanMode(rawValue: defaults.string(forKey: "fanMode") ?? "hover") ?? .hover
        keepOpen = defaults.bool(forKey: "keepOpen")
        fontName = defaults.string(forKey: "fontName") ?? "Virgil"
        textSize = defaults.object(forKey: "textSize") as? Double ?? 21
        animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: "animationSpeed") ?? "normal") ?? .normal
        cloudSyncEnabled = defaults.bool(forKey: "cloudSyncEnabled")
        cloudSyncBookmark = defaults.data(forKey: "cloudSyncBookmark")
        showInDock = defaults.bool(forKey: "showInDock")
        showOnAllScreens = defaults.object(forKey: "showOnAllScreens") as? Bool ?? true
        showOverFullScreen = defaults.bool(forKey: "showOverFullScreen")
        lockNotes = defaults.bool(forKey: "lockNotes")
        let savedAppearance = defaults.string(forKey: "appearance")
        let migrateSystemDefault = savedAppearance == "system" && !defaults.bool(forKey: "lightThemeDefaultApplied")
        appearance = AppearanceMode.initial(saved: savedAppearance, lightDefaultApplied: defaults.bool(forKey: "lightThemeDefaultApplied"))
        if migrateSystemDefault { defaults.set("light", forKey: "appearance") }
        defaults.set(true, forKey: "lightThemeDefaultApplied")
        useDefaultColor = defaults.bool(forKey: "useDefaultColor")
        defaultColor = NoteColor(rawValue: defaults.integer(forKey: "defaultColor")) ?? .amber
        quickShortcut = defaults.data(forKey: "quickShortcut").flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) } ?? .standard
        shortcutAction = ShortcutAction(rawValue: defaults.string(forKey: "shortcutAction") ?? "") ?? .newNote
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
        let statement = try prepare("SELECT id,title,body,color,pinned,created,updated,archived,deleted,sort_index,pin_x,pin_y FROM note\(condition) ORDER BY sort_index")
        defer { sqlite3_finalize(statement) }
        var result: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: idText)) else { continue }
            let title = String(cString: sqlite3_column_text(statement, 1))
            let bytes = sqlite3_column_blob(statement, 2)
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard let bytes else { continue }
            let body = try crypto.decrypt(Data(bytes: bytes, count: count))
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
                pinY: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 11)
            ))
        }
        return result
    }

    func save(_ note: Note) throws {
        let sql = """
          INSERT INTO note(id,title,body,color,pinned,created,updated,archived,deleted,sort_index,pin_x,pin_y)
          VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
          ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,color=excluded.color,
          pinned=excluded.pinned,updated=excluded.updated,archived=excluded.archived,deleted=excluded.deleted,
          sort_index=excluded.sort_index,pin_x=excluded.pin_x,pin_y=excluded.pin_y
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

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var undoNote: Note?
    @Published var errorMessage: String?

    let settings: AppSettings
    private let database: NoteDatabase
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var drafts: [UUID: Note] = [:]
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

    @discardableResult func create() -> Note {
        let next = (notes.map(\Note.sortIndex).max() ?? -1) + 1
        let color = settings.useDefaultColor
            ? settings.defaultColor
            : notes.max { $0.createdAt < $1.createdAt }?.color.next ?? .amber
        let note = Note(color: color, sortIndex: next)
        notes.append(note)
        persist(note)
        return note
    }

    @discardableResult func seedWelcomeIfNeeded() -> Note {
        guard notes.isEmpty else { return notes[0] }
        var note = create()
        note.title = "Getting started"
        note.body = "Hover the right edge of the screen to open your deck.\n\n- Click a card to open it\n- Drag cards up / down to arrange them\n- Pin a note to keep it on your desktop\n- ⌥⌘N makes a new note, ⌥⌘L lists them all\n\nReplace this with your first note."
        update(note, immediate: true)
        return note
    }

    func note(_ id: UUID) -> Note? { drafts[id] ?? notes.first { $0.id == id } }

    func update(_ note: Note, immediate: Bool = false) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var value = note
        value.updatedAt = Date()
        pending[value.id]?.cancel()
        drafts[value.id] = value
        if immediate {
            notes[index] = value
            drafts[value.id] = nil
            persist(value)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let index = self.notes.firstIndex(where: { $0.id == value.id }) else { return }
            self.notes[index] = value
            self.drafts[value.id] = nil
            self.persist(value)
        }
        pending[value.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func flush(_ id: UUID) {
        if let draft = drafts[id] { update(draft, immediate: true) }
    }

    func flushAll() {
        for id in Array(drafts.keys) { flush(id) }
    }

    func archive(_ id: UUID) {
        guard var note = note(id) else { return }
        note.archivedAt = Date(); note.pinned = false
        update(note, immediate: true)
    }

    func restore(_ id: UUID) {
        guard var note = note(id) else { return }
        note.archivedAt = nil
        note.sortIndex = (active.map(\Note.sortIndex).max() ?? -1) + 1
        update(note, immediate: true)
    }

    func duplicate(_ id: UUID) -> Note? {
        guard var copy = note(id) else { return nil }
        copy.id = UUID(); copy.title += " copy"; copy.createdAt = Date(); copy.updatedAt = Date()
        copy.archivedAt = nil; copy.pinned = false; copy.sortIndex = (active.map(\Note.sortIndex).max() ?? -1) + 1
        notes.append(copy); persist(copy)
        return copy
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), let note = note(id) else { return }
        notes.remove(at: index)
        pending[id]?.cancel()
        drafts[id] = nil
        var tombstone = note; tombstone.updatedAt = Date(); tombstone.deletedAt = tombstone.updatedAt
        do { try database.save(tombstone) } catch { errorMessage = error.localizedDescription }
        deletedRecords[id] = tombstone
        undoNote = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.undoNote?.id == id { self?.undoNote = nil }
        }
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
        for (index, var note) in items.enumerated() { note.sortIndex = Double(index); update(note, immediate: true) }
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
                    var note = create(); note.title = url.deletingPathExtension().lastPathComponent; note.body = body; update(note, immediate: true)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func archiveData(_ values: [Note]) throws -> Data { try JSONEncoder.hmn.encode(StickyArchive(notes: values)) }

    private func persist(_ note: Note) {
        pending[note.id] = nil
        do { try database.save(note) } catch { errorMessage = error.localizedDescription }
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
        guard AppearanceMode.initial(saved: nil, lightDefaultApplied: false) == .light,
              AppearanceMode.initial(saved: "system", lightDefaultApplied: false) == .light,
              AppearanceMode.initial(saved: "dark", lightDefaultApplied: true) == .dark else {
            throw SelfCheckFailure("Light is not the default appearance")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("margin-self-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try NoteDatabase(directory: folder, keyService: "app.margin.self-check", keyData: Data(repeating: 7, count: 32))
        var note = Note(title: "Round trip", body: "secret checklist\n- [ ] works", color: .mint)
        try db.save(note)
        let loaded = try db.load()
        precondition(loaded.count == 1 && loaded[0].body == note.body && loaded[0].color == .mint)
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
        let storeSettings = AppSettings()
        let savedDefault = storeSettings.defaultColor
        let savedUseDefault = storeSettings.useDefaultColor
        let savedLastOpenNoteID = storeSettings.lastOpenNoteID
        defer {
            storeSettings.defaultColor = savedDefault; storeSettings.useDefaultColor = savedUseDefault
            storeSettings.lastOpenNoteID = savedLastOpenNoteID
        }
        let rememberedNoteID = UUID()
        storeSettings.lastOpenNoteID = rememberedNoteID
        guard AppSettings().lastOpenNoteID == rememberedNoteID else {
            throw SelfCheckFailure("The last-opened note is not remembered")
        }
        storeSettings.useDefaultColor = true
        storeSettings.defaultColor = .lilac
        let store = NotesStore(settings: storeSettings, database: editDB)
        var edited = store.create()
        guard edited.color == .lilac else { throw SelfCheckFailure("New notes ignore the selected default color") }
        guard store.create().color == .lilac else { throw SelfCheckFailure("Default color mode does not stay fixed") }
        storeSettings.useDefaultColor = false
        guard store.create().color == .amber, store.create().color == .coral else {
            throw SelfCheckFailure("Consecutive new notes do not rotate colors")
        }
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        for index in 0..<100 { edited.body = "keystroke \(index)"; store.update(edited) }
        withExtendedLifetime(observation) {}
        guard publications <= 1 else { throw SelfCheckFailure("Editing published the entire note list \(publications) times") }
        store.flush(edited.id)
        guard store.active.first(where: { $0.id == edited.id })?.body == "keystroke 99",
              try editDB.load().first(where: { $0.id == edited.id })?.body == "keystroke 99" else {
            throw SelfCheckFailure("Closing an editor does not flush its pending draft")
        }
        edited.body = "saved before update"
        store.update(edited)
        store.flushAll()
        guard try editDB.load().first(where: { $0.id == edited.id })?.body == "saved before update" else {
            throw SelfCheckFailure("Quitting for an update loses pending note edits")
        }
        print("Margin self-check passed")
    }
}

struct SelfCheckFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
