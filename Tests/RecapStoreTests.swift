import XCTest
import Foundation

final class RecapStoreTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = Fx.tempFileURL().deletingLastPathComponent().appendingPathComponent("recaps.json", isDirectory: false)
    }

    override func tearDown() {
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// A small generated day, so the store round-trips what the engine writes.
    private func recap(_ key: String, still: Int = 1, worn: Bool = true) -> DayRecap {
        let dayStart = Fx.date("\(key) 04:00")
        var input = RecapInput(
            dayKey: key, dayStart: dayStart, now: Fx.date("\(key) 20:00"), recapTime: Fx.date("\(key) 20:00"),
            userId: "store", restingHistory: [61], coverage: worn ? 0.9 : 0, awakeTrackedHours: worn ? 13 : 0
        )
        input.runs = (0..<still).map { i in
            let peakAt = dayStart.addingTimeInterval(TimeInterval(5 * 3600 + i * 7200))
            return RecapInput.Run(id: "s\(i)", start: peakAt.addingTimeInterval(-180), end: peakAt.addingTimeInterval(600),
                                  peakAt: peakAt, peak: 98, stepsPadded: 3, recoveredAt: peakAt.addingTimeInterval(540))
        }
        return RecapEngine.generate(input, calendar: Fx.calendar())
    }

    func testInMemoryStoreReplacesSameDayAndSortsNewestFirst() throws {
        let store = InMemoryRecapStore()
        try store.save(recap("2026-09-20"))
        try store.save(recap("2026-09-22"))
        try store.save(recap("2026-09-21"))
        XCTAssertEqual(try store.load().map { $0.dayKey }, ["2026-09-22", "2026-09-21", "2026-09-20"])

        try store.save(recap("2026-09-21", still: 3))
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[1].counts.still, 3)

        try store.deleteAll()
        XCTAssertEqual(try store.load(), [])
    }

    func testFileStoreMissingFileLoadsEmpty() throws {
        XCTAssertEqual(try FileRecapStore(url: url).load(), [])
    }

    func testFileStoreRoundTripsNewestFirst() throws {
        let older = recap("2026-09-20", still: 2)
        let newer = recap("2026-09-24", still: 0)
        let notWorn = recap("2026-09-22", worn: false)

        let store = FileRecapStore(url: url)
        try store.save(older)
        try store.save(newer)
        try store.save(notWorn)

        let reloaded = try FileRecapStore(url: url).load()
        XCTAssertEqual(reloaded, [newer, notWorn, older])
        XCTAssertEqual(reloaded[0].text.headline, newer.text.headline)
        XCTAssertTrue(reloaded[1].isNotWorn)
    }

    func testFileStoreReplacesSameDayKey() throws {
        let store = FileRecapStore(url: url)
        try store.save(recap("2026-09-24", still: 1))
        try store.save(recap("2026-09-23", still: 1))
        try store.save(recap("2026-09-24", still: 4))

        let loaded = try store.load()
        XCTAssertEqual(loaded.map { $0.dayKey }, ["2026-09-24", "2026-09-23"])
        XCTAssertEqual(loaded[0].counts.still, 4)
    }

    func testFileStoreDeleteAllRemovesTheFile() throws {
        let store = FileRecapStore(url: url)
        try store.save(recap("2026-09-24"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.load(), [])
        // Deleting twice is not an error.
        try store.deleteAll()
    }

    func testFileStoreWritesOneIso8601Array() throws {
        try FileRecapStore(url: url).save(recap("2026-09-24"))
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("["))
        XCTAssertTrue(raw.contains("\"dayKey\":\"2026-09-24\""), raw)
        XCTAssertTrue(raw.contains("\"generatedAt\":\"2026-09-25T03:00:00Z\""), raw)
    }

    func testDamagedFileThrowsAndIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = FileRecapStore(url: url)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(recap("2026-09-24")))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not json")
    }

    func testUnreadableRecordIsSkippedOnLoad() throws {
        let good = recap("2026-09-22")
        let store = FileRecapStore(url: url)
        try store.save(good)

        let raw = try String(contentsOf: url, encoding: .utf8)
        let patched = "[{\"dayKey\":\"2026-09-23\"}," + String(raw.dropFirst())
        try Data(patched.utf8).write(to: url)

        XCTAssertEqual(try store.load().map { $0.dayKey }, ["2026-09-22"])
    }

    func testWriteOptionsProtectUntilFirstUnlock() {
        let options = FileRecapStore.writeOptions
        XCTAssertTrue(options.contains(.atomic))
        #if os(iOS) || os(watchOS)
        XCTAssertTrue(options.contains(.completeFileProtectionUntilFirstUserAuthentication))
        XCTAssertFalse(options.contains(.completeFileProtection))
        #endif
    }
}
