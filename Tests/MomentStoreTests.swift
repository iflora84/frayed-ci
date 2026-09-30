import XCTest
import Foundation

// Builds moments through Fx.moment(_:) (FrayedCoreTests.swift) so this file
// never spells out Moment's field list; the every-field round trip lives
// next to the model tests.
final class MomentStoreTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = Fx.tempFileURL()
    }

    override func tearDown() {
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testInMemoryStoreUpsertsDeletesAndSortsNewestFirst() throws {
        let store = InMemoryMomentStore()
        let old = Fx.moment("2026-09-01 20:00")
        let new = Fx.moment("2026-09-20 20:00")
        try store.save(old)
        try store.save(new)
        XCTAssertEqual(try store.load().map { $0.id }, [new.id, old.id])

        var edited = old
        edited.note = "edited"
        try store.save(edited)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[1].note, "edited")

        try store.delete(id: new.id)
        XCTAssertEqual(try store.load().map { $0.id }, [old.id])
    }

    func testFileStoreMissingFileLoadsEmpty() throws {
        XCTAssertEqual(try FileMomentStore(url: url).load(), [])
    }

    func testFileStoreRoundTripsAndSortsNewestFirst() throws {
        let newer = Fx.moment("2026-09-24 12:00")
        let older = Fx.moment("2026-09-20 08:00")

        let store = FileMomentStore(url: url)
        try store.save(older)
        try store.save(newer)

        let reloaded = try FileMomentStore(url: url).load()
        XCTAssertEqual(reloaded, [newer, older])
    }

    func testFileStoreWritesOneIso8601Array() throws {
        let m = Fx.moment("2026-09-24 12:00")
        try FileMomentStore(url: url).save(m)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("["))
        XCTAssertTrue(raw.contains("\"start\":\"2026-09-24T19:00:00Z\""), raw)
        XCTAssertTrue(raw.contains("\"end\":\"2026-09-24T19:30:00Z\""), raw)
        XCTAssertFalse(raw.contains("duration"))
    }

    func testFileStoreReplacesSameIdAndDeletes() throws {
        let store = FileMomentStore(url: url)
        var m = Fx.moment("2026-09-24 12:00")
        let other = Fx.moment("2026-09-10 12:00")
        try store.save(m)
        try store.save(other)
        m.note = "edited"
        try store.save(m)

        var loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].note, "edited")

        try store.delete(id: m.id)
        loaded = try store.load()
        XCTAssertEqual(loaded.map { $0.id }, [other.id])
    }

    func testDamagedFileThrowsAndIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = FileMomentStore(url: url)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(Fx.moment("2026-09-24 12:00")))
        XCTAssertThrowsError(try store.delete(id: UUID()))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not json")
    }

    func testInvalidRecordIsSkippedOnLoad() throws {
        let good = Fx.moment("2026-09-22 20:00")
        let store = FileMomentStore(url: url)
        try store.save(good)

        // Prepend a record whose end precedes its start: it parses as JSON
        // and fails Moment's validation, so it is dropped without throwing.
        let raw = try String(contentsOf: url, encoding: .utf8)
        let backwards = """
        {"id":"\(UUID().uuidString)","start":"2026-09-24T19:30:00Z","end":"2026-09-24T19:00:00Z"}
        """
        let patched = "[" + backwards + "," + String(raw.dropFirst())
        try Data(patched.utf8).write(to: url)

        let loaded = try store.load()
        XCTAssertEqual(loaded.map { $0.id }, [good.id])

        let new = Fx.moment("2026-09-24 12:00")
        try store.save(new)
        XCTAssertEqual(try store.load().map { $0.id }, [new.id, good.id])
    }

    func testWriteOptionsProtectUntilFirstUnlock() {
        let options = FileMomentStore.writeOptions
        XCTAssertTrue(options.contains(.atomic))
        #if os(iOS) || os(watchOS)
        XCTAssertTrue(options.contains(.completeFileProtectionUntilFirstUserAuthentication))
        XCTAssertFalse(options.contains(.completeFileProtection))
        #endif
    }
}
