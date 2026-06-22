//
//  ArtistRepository.swift
//  nas-music
//

import Foundation

protocol ArtistRepositoryProtocol {
    func rebuildFromSongs(nasId: String, syncTime: Date) async throws
    func fetchArtists(nasId: String, offset: Int, limit: Int) async throws -> [Artist]
    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Artist]
    func count(nasId: String) async throws -> Int
    func clear(nasId: String) async throws
}

final class ArtistRepository: ArtistRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func rebuildFromSongs(nasId: String, syncTime: Date) async throws {
        try await Task.detached {
            try self.database.transaction { db in
                let delete = try SQLStatement("DELETE FROM artists WHERE nas_id = ?", db: db)
                try delete.bind(nasId, at: 1)
                _ = try delete.step()
                try DatabaseManager.execute("""
                    INSERT INTO artists (
                        id,nas_id,normalized_name,name,song_count,album_count,created_at,updated_at,last_seen_at,is_deleted
                    )
                    SELECT
                        nas_id || ':' || COALESCE(normalized_artist, ''),
                        nas_id,
                        COALESCE(normalized_artist, ''),
                        COALESCE(artist, '未知歌手'),
                        COUNT(*),
                        COUNT(DISTINCT COALESCE(normalized_album, '')),
                        \(syncTime.timeIntervalSince1970),
                        \(syncTime.timeIntervalSince1970),
                        \(syncTime.timeIntervalSince1970),
                        0
                    FROM songs
                    WHERE nas_id = '\(nasId.replacingOccurrences(of: "'", with: "''"))' AND is_deleted = 0
                    GROUP BY nas_id, COALESCE(normalized_artist, '')
                    """, db: db)
            }
        }.value
    }

    func fetchArtists(nasId: String, offset: Int, limit: Int) async throws -> [Artist] {
        try await fetch(sql: """
            SELECT \(Self.columns) FROM artists
            WHERE nas_id = ? AND is_deleted = 0
            ORDER BY name COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .int(limit), .int(offset)])
    }

    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Artist] {
        let pattern = SearchTextNormalizer.escapedLikePattern(for: keyword)
        return try await fetch(sql: """
            SELECT \(Self.columns) FROM artists
            WHERE nas_id = ? AND is_deleted = 0 AND normalized_name LIKE ? ESCAPE '\\'
            ORDER BY name COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .text(pattern), .int(limit), .int(offset)])
    }

    func count(nasId: String) async throws -> Int {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("SELECT COUNT(*) FROM artists WHERE nas_id = ? AND is_deleted = 0", db: db)
                try statement.bind(nasId, at: 1)
                guard try statement.step() else { return 0 }
                return statement.int(0) ?? 0
            }
        }.value
    }

    func clear(nasId: String) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("DELETE FROM artists WHERE nas_id = ?", db: db)
                try statement.bind(nasId, at: 1)
                _ = try statement.step()
            }
        }.value
    }

    private func fetch(sql: String, bindings: [SQLBinding]) async throws -> [Artist] {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement(sql, db: db)
                try bindings.bind(to: statement)
                var artists: [Artist] = []
                while try statement.step() {
                    artists.append(Self.readRecord(from: statement).toDomain())
                }
                return artists
            }
        }.value
    }

    private static let columns = "id,nas_id,normalized_name,name,song_count,album_count,created_at,updated_at,last_seen_at,is_deleted"

    private static func readRecord(from statement: SQLStatement) -> ArtistRecord {
        ArtistRecord(
            id: statement.string(0) ?? "",
            nasId: statement.string(1) ?? "",
            normalizedName: statement.string(2) ?? "",
            name: statement.string(3) ?? "",
            songCount: statement.int(4) ?? 0,
            albumCount: statement.int(5) ?? 0,
            createdAt: Date(timeIntervalSince1970: statement.double(6) ?? 0),
            updatedAt: Date(timeIntervalSince1970: statement.double(7) ?? 0),
            lastSeenAt: Date(timeIntervalSince1970: statement.double(8) ?? 0),
            isDeleted: (statement.int(9) ?? 0) != 0
        )
    }
}
