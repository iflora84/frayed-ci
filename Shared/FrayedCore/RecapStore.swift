import Foundation

protocol RecapStore {
    /// Every cached recap, newest first by dayKey.
    func load() throws -> [DayRecap]
    /// Inserts the recap, or replaces the one with the same dayKey.
    func save(_ recap: DayRecap) throws
    func deleteAll() throws
}

extension DayRecap {
    /// Newest first; the key is "yyyy-MM-dd", so a string sort is a date sort.
    static func newestFirst(_ recaps: [DayRecap]) -> [DayRecap] {
        return recaps.sorted { $0.dayKey > $1.dayKey }
    }
}

final class InMemoryRecapStore: RecapStore {
    private var recaps: [DayRecap]

    init(recaps: [DayRecap] = []) {
        self.recaps = recaps
    }

    func load() throws -> [DayRecap] {
        return DayRecap.newestFirst(recaps)
    }

    func save(_ recap: DayRecap) throws {
        recaps.removeAll { $0.dayKey == recap.dayKey }
        recaps.append(recap)
    }

    func deleteAll() throws {
        recaps.removeAll()
    }
}

/// One JSON array on disk, rewritten atomically on every change, protected
/// until the first unlock after boot like FileMomentStore so a background
/// refresh can still read and write it. The file is excluded from backups:
/// a recap is health data and never leaves the device (RECAP 8).
final class FileRecapStore: RecapStore {
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

    // Only a missing file means "no recaps". A file that cannot be read or
    // parsed must throw, otherwise save() would overwrite the whole cache
    // with one day. A single record that fails to decode is skipped.
    func load() throws -> [DayRecap] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let records = try FileRecapStore.decoder().decode([LenientRecap].self, from: data)
        return DayRecap.newestFirst(records.compactMap { $0.recap })
    }

    private struct LenientRecap: Decodable {
        let recap: DayRecap?

        init(from decoder: Decoder) throws {
            recap = try? DayRecap(from: decoder)
        }
    }

    func save(_ recap: DayRecap) throws {
        var recaps = try load()
        recaps.removeAll { $0.dayKey == recap.dayKey }
        recaps.append(recap)
        try write(recaps)
    }

    func deleteAll() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func write(_ recaps: [DayRecap]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try FileRecapStore.encoder().encode(DayRecap.newestFirst(recaps))
        try data.write(to: url, options: FileRecapStore.writeOptions)
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? file.setResourceValues(values)
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
