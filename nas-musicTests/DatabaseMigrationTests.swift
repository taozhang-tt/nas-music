//
//  DatabaseMigrationTests.swift
//  nas-musicTests
//

import SQLite3
import XCTest
@testable import nas_music

final class DatabaseMigrationTests: XCTestCase {
    func testDatabaseCanBeCreatedAndReopened() throws {
        let url = try makeDatabaseURL()
        _ = try DatabaseManager(path: url)
        _ = try DatabaseManager(path: url)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        let statement = try SQLStatement("PRAGMA user_version", db: db!)
        XCTAssertTrue(try statement.step())
        XCTAssertEqual(statement.int(0), 2)
    }

    private func makeDatabaseURL(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nas-music-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite")
    }
}
