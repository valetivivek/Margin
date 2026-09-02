import AppKit
import Combine
import CryptoKit
import Foundation

private enum CloudSyncError: LocalizedError {
    case invalidManifest, unsupportedManifest, manifestTooLarge, noteTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The Margin sync index contains an invalid note filename."
        case .unsupportedManifest: "This sync folder was created by a newer version of Margin."
        case .manifestTooLarge: "The Margin sync index is unexpectedly large."
        case .noteTooLarge: "A synced note is larger than 10 MB."
        }
    }
}

private struct CloudSyncManifest: Codable, Equatable {
    var version = 1
    var records: [CloudSyncRecord] = []
}

private struct CloudSyncRecord: Codable, Equatable {
    var id: UUID
    var title: String
    var color: NoteColor
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var sortIndex: Double
    var filename: String?
    var contentHash: String?

    init(note: Note, filename: String?, contentHash: String?) {
        id = note.id; title = note.title; color = note.color
        createdAt = note.createdAt; updatedAt = note.updatedAt
        archivedAt = note.archivedAt; deletedAt = note.deletedAt
        sortIndex = note.sortIndex; self.filename = filename; self.contentHash = contentHash
    }

    func note(body: String, title: String? = nil, updatedAt: Date? = nil) -> Note {
        Note(
            id: id, title: title ?? self.title, body: body, color: color, pinned: false,
            createdAt: createdAt, updatedAt: updatedAt ?? self.updatedAt,
            archivedAt: archivedAt, deletedAt: deletedAt, sortIndex: sortIndex
        )
    }
}

struct CloudSyncResult {
    var incoming: [Note]
    var changedCount: Int
}

enum CloudSyncBookmark {
    static func make(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    static func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        } catch {
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        }
    }
}

enum CloudSyncEngine {
    private static let manifestName = ".margin-sync.json"

    static func sync(local: [Note], folder: URL) throws -> CloudSyncResult {
        var coordinatedResult: CloudSyncResult?
        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            do { coordinatedResult = try reconcile(local: local, folder: coordinatedFolder) }
            catch { operationError = error }
        }
        if let operationError { throw operationError }
        if let coordinationError {
            guard coordinationError.domain == NSCocoaErrorDomain,
                  coordinationError.code == CocoaError.fileWriteUnknown.rawValue else { throw coordinationError }
            // Some ordinary local folders reject file coordination; atomic writes remain the safe fallback.
            return try reconcile(local: local, folder: folder)
        }
        guard let coordinatedResult else { throw CocoaError(.fileReadUnknown) }
        return coordinatedResult
    }

    private static func reconcile(local: [Note], folder: URL) throws -> CloudSyncResult {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let manifestURL = folder.appendingPathComponent(manifestName)
        let manifest: CloudSyncManifest
        if manager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            guard data.count <= 5_000_000 else { throw CloudSyncError.manifestTooLarge }
            manifest = try JSONDecoder.hmn.decode(CloudSyncManifest.self, from: data)
            guard manifest.version == 1 else { throw CloudSyncError.unsupportedManifest }
        } else {
            manifest = CloudSyncManifest()
        }

        var oldRecords: [UUID: CloudSyncRecord] = [:]
        manifest.records.forEach { oldRecords[$0.id] = $0 }
        var remoteNotes: [UUID: Note] = [:]
        var remoteHashes: [UUID: String] = [:]

        for record in manifest.records {
            if record.deletedAt != nil {
                remoteNotes[record.id] = record.note(body: "")
                continue
            }
            guard let filename = record.filename else { continue }
            let fileURL = try noteFileURL(filename, in: folder)
            guard manager.fileExists(atPath: fileURL.path) else { continue }
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard (values.fileSize ?? 0) <= 10_000_000 else { throw CloudSyncError.noteTooLarge }
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let parsed = parseMarkdown(text, fallbackTitle: record.title)
            let hash = contentHash(text)
            let modified = values.contentModificationDate ?? record.updatedAt
            let externallyEdited = record.contentHash.map { $0 != hash } ?? (modified > record.updatedAt)
            let updated = externallyEdited ? max(modified, record.updatedAt.addingTimeInterval(0.001)) : record.updatedAt
            remoteNotes[record.id] = record.note(body: parsed.body, title: parsed.title, updatedAt: updated)
            remoteHashes[record.id] = hash
        }

        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let ids = Set(localByID.keys).union(oldRecords.keys)
        var finalRecords: [CloudSyncRecord] = []
        var incoming: [Note] = []
        var changedCount = 0

        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let localNote = localByID[id]
            let remoteNote = remoteNotes[id]
            let oldRecord = oldRecords[id]

            if let localNote, let remoteNote, syncDate(remoteNote) > syncDate(localNote) {
                incoming.append(remoteNote)
                finalRecords.append(recordForRemote(remoteNote, oldRecord: oldRecord, hash: remoteHashes[id]))
                changedCount += 1
            } else if let localNote {
                let record = try write(localNote, replacing: oldRecord, currentHash: remoteHashes[id], in: folder)
                finalRecords.append(record)
                if record != oldRecord { changedCount += 1 }
            } else if let remoteNote {
                incoming.append(remoteNote)
                finalRecords.append(recordForRemote(remoteNote, oldRecord: oldRecord, hash: remoteHashes[id]))
                changedCount += 1
            } else if let oldRecord {
                // Keep metadata for a temporarily unavailable iCloud file; never infer deletion from absence.
                finalRecords.append(oldRecord)
            }
        }

        let output = CloudSyncManifest(records: finalRecords)
        if !manager.fileExists(atPath: manifestURL.path) || output != manifest {
            try JSONEncoder.hmn.encode(output).write(to: manifestURL, options: .atomic)
        }
        return CloudSyncResult(incoming: incoming, changedCount: changedCount)
    }

    private static func write(_ note: Note, replacing oldRecord: CloudSyncRecord?, currentHash: String?, in folder: URL) throws -> CloudSyncRecord {
        let manager = FileManager.default
        if note.deletedAt != nil {
            if let filename = oldRecord?.filename { try? manager.removeItem(at: noteFileURL(filename, in: folder)) }
            return CloudSyncRecord(note: note, filename: nil, contentHash: nil)
        }

        let text = renderMarkdown(note)
        let hash = contentHash(text)
        let filename = "\(safeFilename(note.title))--\(note.id.uuidString.lowercased()).md"
        let fileURL = folder.appendingPathComponent(filename)
        if let oldFilename = oldRecord?.filename, oldFilename != filename {
            try? manager.removeItem(at: noteFileURL(oldFilename, in: folder))
        }
        if oldRecord?.filename != filename || (currentHash ?? oldRecord?.contentHash) != hash || !manager.fileExists(atPath: fileURL.path) {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            try? manager.setAttributes([.modificationDate: note.updatedAt], ofItemAtPath: fileURL.path)
        }
        return CloudSyncRecord(note: note, filename: filename, contentHash: hash)
    }

    private static func recordForRemote(_ note: Note, oldRecord: CloudSyncRecord?, hash: String?) -> CloudSyncRecord {
        CloudSyncRecord(note: note, filename: note.deletedAt == nil ? oldRecord?.filename : nil, contentHash: note.deletedAt == nil ? hash : nil)
    }

    private static func syncDate(_ note: Note) -> Date { note.deletedAt ?? note.updatedAt }

    static func renderMarkdown(_ note: Note) -> String {
        let title = note.title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return "# \(title.isEmpty ? "Untitled note" : title)\n\n\(note.body)"
    }

    static func parseMarkdown(_ text: String, fallbackTitle: String) -> (title: String, body: String) {
        guard text.hasPrefix("# "), let newline = text.firstIndex(of: "\n") else { return (fallbackTitle, text) }
        let rawTitle = String(text[text.index(text.startIndex, offsetBy: 2)..<newline]).trimmingCharacters(in: .whitespaces)
        let title = String(rawTitle.prefix(256))
        var body = String(text[text.index(after: newline)...])
        if body.hasPrefix("\n") { body.removeFirst() }
        return (title.isEmpty ? fallbackTitle : title, body)
    }

    private static func safeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?*\"<>|\0").union(.newlines)
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Untitled note" : cleaned).prefix(80))
    }

    private static func noteFileURL(_ filename: String, in folder: URL) throws -> URL {
        guard !filename.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.lowercased().hasSuffix(".md") else { throw CloudSyncError.invalidManifest }
        return folder.appendingPathComponent(filename, isDirectory: false)
    }

    private static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

final class CloudSyncController: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var status = "Sync is off"
    @Published private(set) var folderName: String?
    @Published private(set) var errorMessage: String?

    private let store: NotesStore
    private let settings: AppSettings
    private let queue = DispatchQueue(label: "app.margin.cloud-sync", qos: .utility)
    private var notesObservation: AnyCancellable?
    private var timer: Timer?
    private var syncAgain = false
    private var generation = 0

    init(store: NotesStore, settings: AppSettings) {
        self.store = store; self.settings = settings
    }

    func start() {
        if notesObservation == nil {
            notesObservation = store.$notes.dropFirst().debounce(for: .milliseconds(450), scheduler: RunLoop.main).sink { [weak self] _ in
                self?.requestSync()
            }
        }
        settings.cloudSyncEnabled ? startRunning() : stopRunning()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.cloudSyncEnabled else { return }
        if enabled, settings.cloudSyncBookmark == nil, !chooseFolder() { return }
        settings.cloudSyncEnabled = enabled
        enabled ? startRunning() : stopRunning()
    }

    @discardableResult func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for Margin notes"
        panel.message = "Choose a folder in iCloud Drive or another synced location. Margin writes one readable Markdown file per note."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            settings.cloudSyncBookmark = try CloudSyncBookmark.make(for: url)
            generation += 1
            folderName = url.lastPathComponent
            errorMessage = nil
            if settings.cloudSyncEnabled { requestSync() }
            return true
        } catch {
            errorMessage = "Margin could not remember that folder. \(error.localizedDescription)"
            return false
        }
    }

    func requestSync() {
        guard settings.cloudSyncEnabled else { return }
        guard !isSyncing else { syncAgain = true; return }
        guard let bookmark = settings.cloudSyncBookmark else {
            errorMessage = "Choose a folder to start syncing."
            status = "Folder required"
            return
        }

        do {
            let resolved = try CloudSyncBookmark.resolve(bookmark)
            let folder = resolved.url
            if resolved.stale {
                settings.cloudSyncBookmark = try CloudSyncBookmark.make(for: folder)
            }
            folderName = folder.lastPathComponent
            errorMessage = nil; status = "Syncing…"; isSyncing = true
            let local = store.recordsForSync()
            let currentGeneration = generation
            queue.async { [weak self] in
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                let result = Result { try CloudSyncEngine.sync(local: local, folder: folder) }
                DispatchQueue.main.async { [weak self] in self?.finish(result, generation: currentGeneration) }
            }
        } catch {
            errorMessage = "Margin can no longer access the sync folder. Choose it again."
            status = "Folder unavailable"
        }
    }

    private func finish(_ result: Result<CloudSyncResult, Error>, generation completedGeneration: Int) {
        isSyncing = false
        guard settings.cloudSyncEnabled else { status = "Sync is off"; return }
        guard completedGeneration == generation else { syncAgain = false; requestSync(); return }
        switch result {
        case .success(let value):
            value.incoming.forEach(store.mergeSynced)
            status = value.changedCount == 0 ? "Up to date" : "Synced \(value.changedCount) \(value.changedCount == 1 ? "change" : "changes")"
            errorMessage = nil
        case .failure(let error):
            status = "Sync paused"
            errorMessage = error.localizedDescription
        }
        if syncAgain { syncAgain = false; requestSync() }
    }

    private func startRunning() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.requestSync() }
        requestSync()
    }

    private func stopRunning() {
        timer?.invalidate(); timer = nil; syncAgain = false
        generation += 1
        status = "Sync is off"; errorMessage = nil
    }
}
