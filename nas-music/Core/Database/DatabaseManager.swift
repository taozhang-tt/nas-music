//
//  DatabaseManager.swift
//  nas-music
//

import Foundation
import SQLite3

final class DatabaseManager: @unchecked Sendable {
    static let shared = try! DatabaseManager()

    let path: URL
    private let queue = DispatchQueue(label: "zero-tt.top.nas-music.database")
    private var db: OpaquePointer?

    init(path: URL? = nil) throws {
        let resolvedPath = try path ?? Self.defaultDatabaseURL()
        self.path = resolvedPath
        try FileManager.default.createDirectory(at: resolvedPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        var opened: OpaquePointer?
        guard sqlite3_open_v2(resolvedPath.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let opened { sqlite3_close(opened) }
            throw DatabaseError.openFailed(message)
        }
        db = opened
        try write { db in
            try Self.execute("PRAGMA foreign_keys = ON", db: db)
            try Self.execute("PRAGMA journal_mode = WAL", db: db)
        }
        try DatabaseMigrator.migrate(self)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func read<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            guard let db else { throw DatabaseError.openFailed("database is closed") }
            return try block(db)
        }
    }

    func write<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            guard let db else { throw DatabaseError.openFailed("database is closed") }
            return try block(db)
        }
    }

    func transaction<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        try write { db in
            try Self.execute("BEGIN IMMEDIATE TRANSACTION", db: db)
            do {
                let result = try block(db)
                try Self.execute("COMMIT", db: db)
                return result
            } catch {
                try? Self.execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func databaseSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? 0
    }

    static func execute(_ sql: String, db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("NASMusic", isDirectory: true).appendingPathComponent("NASMusic.sqlite")
    }
}

final class SQLStatement {
    private let db: OpaquePointer
    private var statement: OpaquePointer?

    init(_ sql: String, db: OpaquePointer) throws {
        self.db = db
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db))) }
    }

    func bind(_ value: Int?, at index: Int32) throws {
        if let value {
            guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func bind(_ value: Int64?, at index: Int32) throws {
        if let value {
            guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        if let value {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw DatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func string(_ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    func int(_ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, index))
    }

    func int64(_ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int64(sqlite3_column_int64(statement, index))
    }

    func double(_ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
