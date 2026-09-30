import Foundation

protocol MomentStore {
    /// All moments, newest first.
    func load() throws -> [Moment]
    /// Inserts the moment, or replaces the one with the same id.
    func save(_ moment: Moment) throws
    func delete(id: UUID) throws
}

final class InMemoryMomentStore: MomentStore {
    private var moments: [Moment]

    init(moments: [Moment] = []) {
        self.moments = moments
    }

    func load() throws -> [Moment] {
        return Moment.newestFirst(moments)
    }

    func save(_ moment: Moment) throws {
        moments.removeAll { $0.id == moment.id }
        moments.append(moment)
    }

    func delete(id: UUID) throws {
        moments.removeAll { $0.id == id }
    }
}

/// One JSON array on disk, rewritten atomically on every change.
///
/// On iOS and watchOS the file is protected until the first unlock after
/// boot, so a background refresh task and an App Intent run from the lock
/// screen can still read and append. Face ID stays the UI lock; the file
/// never leaves the device or its encrypted backup.
final class FileMomentStore: MomentStore {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    static var writeOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }

    // Only a missing file means "no moments". Any other failure (the device
    // has not been unlocked since boot and the file is protected, or the JSON
    // is damaged) must throw, otherwise save() would overwrite the whole
    // history with one moment. A single record that parses but fails
    // validation is skipped instead, so one bad entry cannot lock the user
    // out of saving; it is gone after the next write.
    func load() throws -> [Moment] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let records = try FileMomentStore.decoder().decode([LenientMoment].self, from: data)
        return Moment.newestFirst(records.compactMap { $0.moment })
    }

    private struct LenientMoment: Decodable {
        let moment: Moment?

        init(from decoder: Decoder) throws {
            moment = try? Moment(from: decoder)
        }
    }

    func save(_ moment: Moment) throws {
        var moments = try load()
        moments.removeAll { $0.id == moment.id }
        moments.append(moment)
        try write(moments)
    }

    func delete(id: UUID) throws {
        var moments = try load()
        moments.removeAll { $0.id == id }
        try write(moments)
    }

    private func write(_ moments: [Moment]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try FileMomentStore.encoder().encode(Moment.newestFirst(moments))
        try data.write(to: url, options: FileMomentStore.writeOptions)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
