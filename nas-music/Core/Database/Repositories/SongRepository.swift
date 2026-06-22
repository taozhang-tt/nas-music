//
//  SongRepository.swift
//  nas-music
//

import Foundation
import SQLite3

protocol SongRepositoryProtocol {
    func upsert(songs: [Song], nasId: String, syncTime: Date) async throws
    func fetchSongs(nasId: String, offset: Int, limit: Int) async throws -> [Song]
    func fetchSongs(nasId: String, album: String, albumArtist: String?, offset: Int, limit: Int) async throws -> [Song]
    func fetchSongs(nasId: String, artist: String, offset: Int, limit: Int) async throws -> [Song]
    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Song]
    func count(nasId: String) async throws -> Int
    func markMissingAsDeleted(nasId: String, lastSeenBefore syncTime: Date) async throws
    func clear(nasId: String) async throws
}

final class SongRepository: SongRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func upsert(songs: [Song], nasId: String, syncTime: Date) async throws {
        try await Task.detached {
            let records = songs.map { $0.toRecord(nasId: nasId, syncTime: syncTime) }
            try self.database.transaction { db in
                let statement = try SQLStatement(Self.upsertSQL, db: db)
                for record in records {
                    try Self.bind(record, to: statement)
                    _ = try statement.step()
                    statement.reset()
                }
            }
        }.value
    }

    func fetchSongs(nasId: String, offset: Int, limit: Int) async throws -> [Song] {
        try await fetch(sql: """
            SELECT \(Self.columns) FROM songs
            WHERE nas_id = ? AND is_deleted = 0
            ORDER BY updated_at DESC, title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .int(limit), .int(offset)])
    }

    func fetchSongs(nasId: String, album: String, albumArtist: String?, offset: Int, limit: Int) async throws -> [Song] {
        var bindings: [SQLBinding] = [.text(nasId), .text(SearchTextNormalizer.normalize(album))]
        var clause = "nas_id = ? AND is_deleted = 0 AND normalized_album = ?"
        if let albumArtist, !albumArtist.isEmpty {
            clause += " AND (album_artist = ? OR normalized_artist = ?)"
            bindings.append(.text(albumArtist))
            bindings.append(.text(SearchTextNormalizer.normalize(albumArtist)))
        }
        bindings.append(contentsOf: [.int(limit), .int(offset)])
        return try await fetch(sql: """
            SELECT \(Self.columns) FROM songs
            WHERE \(clause)
            ORDER BY disc_number ASC, track_number ASC, title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: bindings)
    }

    func fetchSongs(nasId: String, artist: String, offset: Int, limit: Int) async throws -> [Song] {
        try await fetch(sql: """
            SELECT \(Self.columns) FROM songs
            WHERE nas_id = ? AND is_deleted = 0 AND normalized_artist = ?
            ORDER BY album COLLATE NOCASE ASC, disc_number ASC, track_number ASC, title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .text(SearchTextNormalizer.normalize(artist)), .int(limit), .int(offset)])
    }

    func search(nasId: String, keyword: String, offset: Int, limit: Int) async throws -> [Song] {
        let pattern = SearchTextNormalizer.escapedLikePattern(for: keyword)
        return try await fetch(sql: """
            SELECT \(Self.columns) FROM songs
            WHERE nas_id = ? AND is_deleted = 0
              AND (normalized_title LIKE ? ESCAPE '\\'
                   OR normalized_artist LIKE ? ESCAPE '\\'
                   OR normalized_album LIKE ? ESCAPE '\\'
                   OR album_artist LIKE ? ESCAPE '\\')
            ORDER BY title COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """, bindings: [.text(nasId), .text(pattern), .text(pattern), .text(pattern), .text(pattern), .int(limit), .int(offset)])
    }

    func count(nasId: String) async throws -> Int {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("SELECT COUNT(*) FROM songs WHERE nas_id = ? AND is_deleted = 0", db: db)
                try statement.bind(nasId, at: 1)
                guard try statement.step() else { return 0 }
                return statement.int(0) ?? 0
            }
        }.value
    }

    func markMissingAsDeleted(nasId: String, lastSeenBefore syncTime: Date) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("UPDATE songs SET is_deleted = 1, updated_at = ? WHERE nas_id = ? AND last_seen_at < ?", db: db)
                try statement.bind(Date().timeIntervalSince1970, at: 1)
                try statement.bind(nasId, at: 2)
                try statement.bind(syncTime.timeIntervalSince1970, at: 3)
                _ = try statement.step()
            }
        }.value
    }

    func clear(nasId: String) async throws {
        try await Task.detached {
            try self.database.transaction { db in
                for table in ["playlist_songs", "songs"] {
                    let statement = try SQLStatement(table == "playlist_songs"
                        ? "DELETE FROM playlist_songs WHERE song_id IN (SELECT id FROM songs WHERE nas_id = ?)"
                        : "DELETE FROM songs WHERE nas_id = ?", db: db)
                    try statement.bind(nasId, at: 1)
                    _ = try statement.step()
                }
            }
        }.value
    }

    private func fetch(sql: String, bindings: [SQLBinding]) async throws -> [Song] {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement(sql, db: db)
                try bindings.bind(to: statement)
                var songs: [Song] = []
                while try statement.step() {
                    songs.append(Self.readRecord(from: statement).toDomain())
                }
                return songs
            }
        }.value
    }

    private static let columns = """
        id,nas_id,source_id,title,normalized_title,artist,normalized_artist,album,normalized_album,album_artist,
        duration,track_number,disc_number,year,genre,file_extension,bitrate,sample_rate,file_size,cover_id,path,
        created_at,updated_at,last_seen_at,is_deleted
        """

    private static let upsertSQL = """
        INSERT INTO songs (
            id,nas_id,source_id,title,normalized_title,artist,normalized_artist,album,normalized_album,album_artist,
            duration,track_number,disc_number,year,genre,file_extension,bitrate,sample_rate,file_size,cover_id,path,
            created_at,updated_at,last_seen_at,is_deleted
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(nas_id, source_id) DO UPDATE SET
            title=excluded.title,
            normalized_title=excluded.normalized_title,
            artist=excluded.artist,
            normalized_artist=excluded.normalized_artist,
            album=excluded.album,
            normalized_album=excluded.normalized_album,
            album_artist=excluded.album_artist,
            duration=excluded.duration,
            track_number=excluded.track_number,
            disc_number=excluded.disc_number,
            year=excluded.year,
            genre=excluded.genre,
            file_extension=excluded.file_extension,
            bitrate=excluded.bitrate,
            sample_rate=excluded.sample_rate,
            file_size=excluded.file_size,
            cover_id=excluded.cover_id,
            path=excluded.path,
            updated_at=excluded.updated_at,
            last_seen_at=excluded.last_seen_at,
            is_deleted=0
        """

    private static func bind(_ record: SongRecord, to statement: SQLStatement) throws {
        try statement.bind(record.id, at: 1)
        try statement.bind(record.nasId, at: 2)
        try statement.bind(record.sourceId, at: 3)
        try statement.bind(record.title, at: 4)
        try statement.bind(record.normalizedTitle, at: 5)
        try statement.bind(record.artist, at: 6)
        try statement.bind(record.normalizedArtist, at: 7)
        try statement.bind(record.album, at: 8)
        try statement.bind(record.normalizedAlbum, at: 9)
        try statement.bind(record.albumArtist, at: 10)
        try statement.bind(record.duration, at: 11)
        try statement.bind(record.trackNumber, at: 12)
        try statement.bind(record.discNumber, at: 13)
        try statement.bind(record.year, at: 14)
        try statement.bind(record.genre, at: 15)
        try statement.bind(record.fileExtension, at: 16)
        try statement.bind(record.bitrate, at: 17)
        try statement.bind(record.sampleRate, at: 18)
        try statement.bind(record.fileSize, at: 19)
        try statement.bind(record.coverId, at: 20)
        try statement.bind(record.path, at: 21)
        try statement.bind(record.createdAt.timeIntervalSince1970, at: 22)
        try statement.bind(record.updatedAt.timeIntervalSince1970, at: 23)
        try statement.bind(record.lastSeenAt.timeIntervalSince1970, at: 24)
        try statement.bind(record.isDeleted ? 1 : 0, at: 25)
    }

    static func readRecord(from statement: SQLStatement) -> SongRecord {
        SongRecord(
            id: statement.string(0) ?? "",
            nasId: statement.string(1) ?? "",
            sourceId: statement.string(2) ?? "",
            title: statement.string(3) ?? "",
            normalizedTitle: statement.string(4),
            artist: statement.string(5),
            normalizedArtist: statement.string(6),
            album: statement.string(7),
            normalizedAlbum: statement.string(8),
            albumArtist: statement.string(9),
            duration: statement.double(10),
            trackNumber: statement.int(11),
            discNumber: statement.int(12),
            year: statement.int(13),
            genre: statement.string(14),
            fileExtension: statement.string(15),
            bitrate: statement.int(16),
            sampleRate: statement.int(17),
            fileSize: statement.int64(18),
            coverId: statement.string(19),
            path: statement.string(20),
            createdAt: Date(timeIntervalSince1970: statement.double(21) ?? 0),
            updatedAt: Date(timeIntervalSince1970: statement.double(22) ?? 0),
            lastSeenAt: Date(timeIntervalSince1970: statement.double(23) ?? 0),
            isDeleted: (statement.int(24) ?? 0) != 0
        )
    }
}

enum SQLBinding {
    case text(String?)
    case int(Int)
    case int64(Int64?)
    case double(Double?)
}

extension Array where Element == SQLBinding {
    func bind(to statement: SQLStatement) throws {
        for (offset, binding) in enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let value):
                try statement.bind(value, at: index)
            case .int(let value):
                try statement.bind(value, at: index)
            case .int64(let value):
                try statement.bind(value, at: index)
            case .double(let value):
                try statement.bind(value, at: index)
            }
        }
    }
}
