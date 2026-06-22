//
//  AlbumRepository.swift
//  nas-music
//

import Foundation

protocol AlbumRepositoryProtocol {
    func rebuildFromSongs(nasId: String, syncTime: Date) async throws
    func fetchAlbums(nasId: String, offset: Int, limit: Int) async throws -> [Album]
    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Album]
    func count(nasId: String) async throws -> Int
    func clear(nasId: String) async throws
}

final class AlbumRepository: AlbumRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func rebuildFromSongs(nasId: String, syncTime: Date) async throws {
        try await Task.detached {
            try self.database.transaction { db in
                let delete = try SQLStatement("DELETE FROM albums WHERE nas_id = ?", db: db)
                try delete.bind(nasId, at: 1)
                _ = try delete.step()
                try DatabaseManager.execute("""
                    INSERT INTO albums (
                        id,nas_id,source_key,title,normalized_title,artist,normalized_artist,album_artist,year,
                        song_count,total_duration,cover_id,created_at,updated_at,last_seen_at,is_deleted
                    )
                    SELECT
                        nas_id || ':' || COALESCE(normalized_album, '') || '|' || COALESCE(normalized_artist, ''),
                        nas_id,
                        COALESCE(normalized_album, '') || '|' || COALESCE(normalized_artist, ''),
                        COALESCE(album, '未知专辑'),
                        normalized_album,
                        artist,
                        normalized_artist,
                        album_artist,
                        MIN(year),
                        COUNT(*),
                        SUM(duration),
                        MAX(cover_id),
                        \(syncTime.timeIntervalSince1970),
                        \(syncTime.timeIntervalSince1970),
                        \(syncTime.timeIntervalSince1970),
                        0
                    FROM songs
                    WHERE nas_id = '\(nasId.replacingOccurrences(of: "'", with: "''"))' AND is_deleted = 0
                    GROUP BY nas_id, COALESCE(normalized_album, ''), COALESCE(normalized_artist, '')
                    """, db: db)
            }
        }.value
    }

    func fetchAlbums(nasId: String, offset: Int, limit: Int) async throws -> [Album] {
        try await fetch(sql: """
            SELECT \(Self.columns) FROM albums
            WHERE nas_id = ? AND is_deleted = 0
            ORDER BY title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .int(limit), .int(offset)])
    }

    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Album] {
        let pattern = SearchTextNormalizer.escapedLikePattern(for: keyword)
        return try await fetch(sql: """
            SELECT \(Self.columns) FROM albums
            WHERE nas_id = ? AND is_deleted = 0
              AND (normalized_title LIKE ? ESCAPE '\\' OR normalized_artist LIKE ? ESCAPE '\\')
            ORDER BY title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .text(pattern), .text(pattern), .int(limit), .int(offset)])
    }

    func count(nasId: String) async throws -> Int {
        try await count(table: "albums", nasId: nasId)
    }

    func clear(nasId: String) async throws {
        try await clear(table: "albums", nasId: nasId)
    }

    private func fetch(sql: String, bindings: [SQLBinding]) async throws -> [Album] {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement(sql, db: db)
                try bindings.bind(to: statement)
                var albums: [Album] = []
                while try statement.step() {
                    albums.append(Self.readRecord(from: statement).toDomain())
                }
                return albums
            }
        }.value
    }

    private func count(table: String, nasId: String) async throws -> Int {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("SELECT COUNT(*) FROM \(table) WHERE nas_id = ? AND is_deleted = 0", db: db)
                try statement.bind(nasId, at: 1)
                guard try statement.step() else { return 0 }
                return statement.int(0) ?? 0
            }
        }.value
    }

    private func clear(table: String, nasId: String) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("DELETE FROM \(table) WHERE nas_id = ?", db: db)
                try statement.bind(nasId, at: 1)
                _ = try statement.step()
            }
        }.value
    }

    private static let columns = "id,nas_id,source_key,title,normalized_title,artist,normalized_artist,album_artist,year,song_count,total_duration,cover_id,created_at,updated_at,last_seen_at,is_deleted"

    private static func readRecord(from statement: SQLStatement) -> AlbumRecord {
        AlbumRecord(
            id: statement.string(0) ?? "",
            nasId: statement.string(1) ?? "",
            sourceKey: statement.string(2) ?? "",
            title: statement.string(3) ?? "",
            normalizedTitle: statement.string(4),
            artist: statement.string(5),
            normalizedArtist: statement.string(6),
            albumArtist: statement.string(7),
            year: statement.int(8),
            songCount: statement.int(9) ?? 0,
            totalDuration: statement.double(10),
            coverId: statement.string(11),
            createdAt: Date(timeIntervalSince1970: statement.double(12) ?? 0),
            updatedAt: Date(timeIntervalSince1970: statement.double(13) ?? 0),
            lastSeenAt: Date(timeIntervalSince1970: statement.double(14) ?? 0),
            isDeleted: (statement.int(15) ?? 0) != 0
        )
    }
}
