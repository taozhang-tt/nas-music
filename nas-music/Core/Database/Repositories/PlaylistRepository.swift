//
//  PlaylistRepository.swift
//  nas-music
//

import Foundation

protocol PlaylistRepositoryProtocol {
    func upsert(playlists: [Playlist], nasId: String, syncTime: Date) async throws
    func fetchPlaylists(nasId: String, offset: Int, limit: Int) async throws -> [Playlist]
    func count(nasId: String) async throws -> Int
    func clear(nasId: String) async throws
}

final class PlaylistRepository: PlaylistRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func upsert(playlists: [Playlist], nasId: String, syncTime: Date) async throws {
        try await Task.detached {
            let records = playlists.map { $0.toRecord(nasId: nasId, syncTime: syncTime) }
            try self.database.transaction { db in
                let statement = try SQLStatement("""
                    INSERT INTO playlists (
                        id,nas_id,source_id,name,normalized_name,song_count,cover_id,created_at,updated_at,last_seen_at,is_deleted
                    ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(nas_id, source_id) DO UPDATE SET
                        name=excluded.name,
                        normalized_name=excluded.normalized_name,
                        song_count=excluded.song_count,
                        cover_id=excluded.cover_id,
                        updated_at=excluded.updated_at,
                        last_seen_at=excluded.last_seen_at,
                        is_deleted=0
                    """, db: db)
                for record in records {
                    try statement.bind(record.id, at: 1)
                    try statement.bind(record.nasId, at: 2)
                    try statement.bind(record.sourceId, at: 3)
                    try statement.bind(record.name, at: 4)
                    try statement.bind(record.normalizedName, at: 5)
                    try statement.bind(record.songCount, at: 6)
                    try statement.bind(record.coverId, at: 7)
                    try statement.bind(record.createdAt.timeIntervalSince1970, at: 8)
                    try statement.bind(record.updatedAt.timeIntervalSince1970, at: 9)
                    try statement.bind(record.lastSeenAt.timeIntervalSince1970, at: 10)
                    try statement.bind(record.isDeleted ? 1 : 0, at: 11)
                    _ = try statement.step()
                    statement.reset()
                }
            }
        }.value
    }

    func fetchPlaylists(nasId: String, offset: Int, limit: Int) async throws -> [Playlist] {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("""
                    SELECT id,nas_id,source_id,name,normalized_name,song_count,cover_id,created_at,updated_at,last_seen_at,is_deleted
                    FROM playlists
                    WHERE nas_id = ? AND is_deleted = 0
                    ORDER BY name COLLATE NOCASE ASC
                    LIMIT ? OFFSET ?
                    """, db: db)
                try statement.bind(nasId, at: 1)
                try statement.bind(limit, at: 2)
                try statement.bind(offset, at: 3)
                var playlists: [Playlist] = []
                while try statement.step() {
                    playlists.append(PlaylistRecord(
                        id: statement.string(0) ?? "",
                        nasId: statement.string(1) ?? "",
                        sourceId: statement.string(2) ?? "",
                        name: statement.string(3) ?? "",
                        normalizedName: statement.string(4),
                        songCount: statement.int(5) ?? 0,
                        coverId: statement.string(6),
                        createdAt: Date(timeIntervalSince1970: statement.double(7) ?? 0),
                        updatedAt: Date(timeIntervalSince1970: statement.double(8) ?? 0),
                        lastSeenAt: Date(timeIntervalSince1970: statement.double(9) ?? 0),
                        isDeleted: (statement.int(10) ?? 0) != 0
                    ).toDomain())
                }
                return playlists
            }
        }.value
    }

    func count(nasId: String) async throws -> Int {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("SELECT COUNT(*) FROM playlists WHERE nas_id = ? AND is_deleted = 0", db: db)
                try statement.bind(nasId, at: 1)
                guard try statement.step() else { return 0 }
                return statement.int(0) ?? 0
            }
        }.value
    }

    func clear(nasId: String) async throws {
        try await Task.detached {
            try self.database.transaction { db in
                let playlistSongs = try SQLStatement("DELETE FROM playlist_songs WHERE playlist_id IN (SELECT id FROM playlists WHERE nas_id = ?)", db: db)
                try playlistSongs.bind(nasId, at: 1)
                _ = try playlistSongs.step()
                let playlists = try SQLStatement("DELETE FROM playlists WHERE nas_id = ?", db: db)
                try playlists.bind(nasId, at: 1)
                _ = try playlists.step()
            }
        }.value
    }
}
