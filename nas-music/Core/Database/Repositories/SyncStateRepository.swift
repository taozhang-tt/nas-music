//
//  SyncStateRepository.swift
//  nas-music
//

import Foundation

protocol SyncStateRepositoryProtocol {
    func get(nasId: String) async throws -> SyncStateRecord?
    func upsert(_ state: SyncStateRecord) async throws
    func clear(nasId: String) async throws
}

final class SyncStateRepository: SyncStateRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func get(nasId: String) async throws -> SyncStateRecord? {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("""
                    SELECT nas_id,status,last_full_sync_at,last_successful_sync_at,last_failed_sync_at,last_error_message,
                           synced_song_count,total_song_count,album_count,artist_count,playlist_count,current_offset
                    FROM sync_state WHERE nas_id = ?
                    """, db: db)
                try statement.bind(nasId, at: 1)
                guard try statement.step() else { return nil }
                return SyncStateRecord(
                    nasId: statement.string(0) ?? "",
                    status: statement.string(1) ?? "idle",
                    lastFullSyncAt: statement.double(2).map(Date.init(timeIntervalSince1970:)),
                    lastSuccessfulSyncAt: statement.double(3).map(Date.init(timeIntervalSince1970:)),
                    lastFailedSyncAt: statement.double(4).map(Date.init(timeIntervalSince1970:)),
                    lastErrorMessage: statement.string(5),
                    syncedSongCount: statement.int(6) ?? 0,
                    totalSongCount: statement.int(7),
                    albumCount: statement.int(8) ?? 0,
                    artistCount: statement.int(9) ?? 0,
                    playlistCount: statement.int(10) ?? 0,
                    currentOffset: statement.int(11) ?? 0
                )
            }
        }.value
    }

    func upsert(_ state: SyncStateRecord) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("""
                    INSERT INTO sync_state (
                        nas_id,status,last_full_sync_at,last_successful_sync_at,last_failed_sync_at,last_error_message,
                        synced_song_count,total_song_count,album_count,artist_count,playlist_count,current_offset
                    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(nas_id) DO UPDATE SET
                        status=excluded.status,
                        last_full_sync_at=excluded.last_full_sync_at,
                        last_successful_sync_at=excluded.last_successful_sync_at,
                        last_failed_sync_at=excluded.last_failed_sync_at,
                        last_error_message=excluded.last_error_message,
                        synced_song_count=excluded.synced_song_count,
                        total_song_count=excluded.total_song_count,
                        album_count=excluded.album_count,
                        artist_count=excluded.artist_count,
                        playlist_count=excluded.playlist_count,
                        current_offset=excluded.current_offset
                    """, db: db)
                try statement.bind(state.nasId, at: 1)
                try statement.bind(state.status, at: 2)
                try statement.bind(state.lastFullSyncAt?.timeIntervalSince1970, at: 3)
                try statement.bind(state.lastSuccessfulSyncAt?.timeIntervalSince1970, at: 4)
                try statement.bind(state.lastFailedSyncAt?.timeIntervalSince1970, at: 5)
                try statement.bind(state.lastErrorMessage, at: 6)
                try statement.bind(state.syncedSongCount, at: 7)
                try statement.bind(state.totalSongCount, at: 8)
                try statement.bind(state.albumCount, at: 9)
                try statement.bind(state.artistCount, at: 10)
                try statement.bind(state.playlistCount, at: 11)
                try statement.bind(state.currentOffset, at: 12)
                _ = try statement.step()
            }
        }.value
    }

    func clear(nasId: String) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("DELETE FROM sync_state WHERE nas_id = ?", db: db)
                try statement.bind(nasId, at: 1)
                _ = try statement.step()
            }
        }.value
    }
}
