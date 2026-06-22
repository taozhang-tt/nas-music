//
//  DatabaseMigrator.swift
//  nas-music
//

import Foundation
import SQLite3

enum DatabaseMigrator {
    static let currentVersion: Int32 = 1

    static func migrate(_ manager: DatabaseManager) throws {
        try manager.write { db in
            let version = try userVersion(db)
            guard version < currentVersion else { return }
            do {
                try DatabaseManager.execute("BEGIN IMMEDIATE TRANSACTION", db: db)
                if version < 1 {
                    try createVersion1(db)
                    try DatabaseManager.execute("PRAGMA user_version = \(currentVersion)", db: db)
                }
                try DatabaseManager.execute("COMMIT", db: db)
            } catch {
                try? DatabaseManager.execute("ROLLBACK", db: db)
                throw DatabaseError.migrationFailed(error.localizedDescription)
            }
        }
    }

    private static func userVersion(_ db: OpaquePointer) throws -> Int32 {
        let statement = try SQLStatement("PRAGMA user_version", db: db)
        guard try statement.step() else {
            throw DatabaseError.stepFailed("Unable to read database user_version")
        }
        return Int32(statement.int(0) ?? 0)
    }

    private static func createVersion1(_ db: OpaquePointer) throws {
        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS songs (
            id TEXT PRIMARY KEY NOT NULL,
            nas_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            title TEXT NOT NULL,
            normalized_title TEXT,
            artist TEXT,
            normalized_artist TEXT,
            album TEXT,
            normalized_album TEXT,
            album_artist TEXT,
            duration REAL,
            track_number INTEGER,
            disc_number INTEGER,
            year INTEGER,
            genre TEXT,
            file_extension TEXT,
            bitrate INTEGER,
            sample_rate INTEGER,
            file_size INTEGER,
            cover_id TEXT,
            path TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(nas_id, source_id)
        );
        """, db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_songs_nas_id ON songs(nas_id);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_songs_title ON songs(nas_id, normalized_title);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs(nas_id, normalized_artist);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_songs_album ON songs(nas_id, normalized_album);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_songs_last_seen ON songs(nas_id, last_seen_at);", db: db)

        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS albums (
            id TEXT PRIMARY KEY NOT NULL,
            nas_id TEXT NOT NULL,
            source_key TEXT NOT NULL,
            title TEXT NOT NULL,
            normalized_title TEXT,
            artist TEXT,
            normalized_artist TEXT,
            album_artist TEXT,
            year INTEGER,
            song_count INTEGER NOT NULL DEFAULT 0,
            total_duration REAL,
            cover_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(nas_id, source_key)
        );
        """, db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_albums_nas_id ON albums(nas_id);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_albums_title ON albums(nas_id, normalized_title);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_albums_artist ON albums(nas_id, normalized_artist);", db: db)

        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS artists (
            id TEXT PRIMARY KEY NOT NULL,
            nas_id TEXT NOT NULL,
            normalized_name TEXT NOT NULL,
            name TEXT NOT NULL,
            song_count INTEGER NOT NULL DEFAULT 0,
            album_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(nas_id, normalized_name)
        );
        """, db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_artists_nas_id ON artists(nas_id);", db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(nas_id, normalized_name);", db: db)

        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY NOT NULL,
            nas_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            name TEXT NOT NULL,
            normalized_name TEXT,
            song_count INTEGER NOT NULL DEFAULT 0,
            cover_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(nas_id, source_id)
        );
        """, db: db)
        try DatabaseManager.execute("CREATE INDEX IF NOT EXISTS idx_playlists_nas_id ON playlists(nas_id);", db: db)

        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS playlist_songs (
            playlist_id TEXT NOT NULL,
            song_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY(playlist_id, song_id)
        );
        """, db: db)

        try DatabaseManager.execute("""
        CREATE TABLE IF NOT EXISTS sync_state (
            nas_id TEXT PRIMARY KEY NOT NULL,
            status TEXT NOT NULL,
            last_full_sync_at REAL,
            last_successful_sync_at REAL,
            last_failed_sync_at REAL,
            last_error_message TEXT,
            synced_song_count INTEGER NOT NULL DEFAULT 0,
            total_song_count INTEGER,
            album_count INTEGER NOT NULL DEFAULT 0,
            artist_count INTEGER NOT NULL DEFAULT 0,
            playlist_count INTEGER NOT NULL DEFAULT 0,
            current_offset INTEGER NOT NULL DEFAULT 0
        );
        """, db: db)
    }
}
