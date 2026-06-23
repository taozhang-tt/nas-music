//
//  MusicLibrarySyncService.swift
//  nas-music
//

import Foundation
import Combine
import OSLog

@MainActor
final class MusicLibrarySyncService: ObservableObject {
    @Published private(set) var status: MusicLibrarySyncStatus = .idle
    @Published private(set) var localStats = MusicLibraryLocalStats(
        nasName: nil,
        songCount: 0,
        albumCount: 0,
        artistCount: 0,
        playlistCount: 0,
        lastSuccessfulSyncAt: nil,
        databaseSize: 0
    )

    private static let logger = Logger(subsystem: "zero-tt.top.nas-music", category: "MusicSync")

    private let sessionManager: NASSessionManager
    private let songRepository: SongRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let artistRepository: ArtistRepositoryProtocol
    private let playlistRepository: PlaylistRepositoryProtocol
    private let syncStateRepository: SyncStateRepositoryProtocol
    private let database: DatabaseManager
    private let metadataWritebackService: MetadataWritebackService?
    private var syncTask: Task<Void, Never>?

    init(
        sessionManager: NASSessionManager,
        songRepository: SongRepositoryProtocol = SongRepository(),
        albumRepository: AlbumRepositoryProtocol = AlbumRepository(),
        artistRepository: ArtistRepositoryProtocol = ArtistRepository(),
        playlistRepository: PlaylistRepositoryProtocol = PlaylistRepository(),
        syncStateRepository: SyncStateRepositoryProtocol = SyncStateRepository(),
        database: DatabaseManager = .shared,
        metadataWritebackService: MetadataWritebackService? = nil
    ) {
        self.sessionManager = sessionManager
        self.songRepository = songRepository
        self.albumRepository = albumRepository
        self.artistRepository = artistRepository
        self.playlistRepository = playlistRepository
        self.syncStateRepository = syncStateRepository
        self.database = database
        self.metadataWritebackService = metadataWritebackService
    }

    var isSyncing: Bool {
        if case .syncing = status { return true }
        if case .preparing = status { return true }
        if case .rebuildingAlbums = status { return true }
        if case .rebuildingArtists = status { return true }
        return false
    }

    func syncLibrary() async {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performSync(clearFirst: false)
            await MainActor.run { self.syncTask = nil }
        }
        await syncTask?.value
    }

    func cancelSync() {
        syncTask?.cancel()
    }

    func rebuildLibrary() async {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performSync(clearFirst: true)
            await MainActor.run { self.syncTask = nil }
        }
        await syncTask?.value
    }

    func clearLocalIndex() async {
        guard let nasId = sessionManager.config?.id.uuidString else { return }
        do {
            try await songRepository.clear(nasId: nasId)
            try await albumRepository.clear(nasId: nasId)
            try await artistRepository.clear(nasId: nasId)
            try await playlistRepository.clear(nasId: nasId)
            try await syncStateRepository.clear(nasId: nasId)
            status = .idle
            await refreshLocalStats()
        } catch {
            status = .failed(message: MusicLibrarySyncError.databaseWriteFailed.localizedDescription)
        }
    }

    func refreshLocalStats() async {
        guard let config = sessionManager.config else {
            localStats = MusicLibraryLocalStats(
                nasName: nil,
                songCount: 0,
                albumCount: 0,
                artistCount: 0,
                playlistCount: 0,
                lastSuccessfulSyncAt: nil,
                databaseSize: database.databaseSize()
            )
            return
        }

        let nasId = config.id.uuidString
        do {
            async let songCount = songRepository.count(nasId: nasId)
            async let albumCount = albumRepository.count(nasId: nasId)
            async let artistCount = artistRepository.count(nasId: nasId)
            async let playlistCount = playlistRepository.count(nasId: nasId)
            async let syncState = syncStateRepository.get(nasId: nasId)
            let loaded = try await (songCount, albumCount, artistCount, playlistCount, syncState)
            localStats = MusicLibraryLocalStats(
                nasName: config.displayName ?? config.name,
                songCount: loaded.0,
                albumCount: loaded.1,
                artistCount: loaded.2,
                playlistCount: loaded.3,
                lastSuccessfulSyncAt: loaded.4?.lastSuccessfulSyncAt,
                databaseSize: database.databaseSize()
            )
        } catch {
            localStats = MusicLibraryLocalStats(
                nasName: config.displayName ?? config.name,
                songCount: 0,
                albumCount: 0,
                artistCount: 0,
                playlistCount: 0,
                lastSuccessfulSyncAt: nil,
                databaseSize: database.databaseSize()
            )
        }
    }

    private func performSync(clearFirst: Bool) async {
        do {
            status = .preparing
            guard let config = sessionManager.config else { throw MusicLibrarySyncError.nasNotConfigured }
            guard sessionManager.state == .connected else { throw MusicLibrarySyncError.nasNotConnected }
            let nasId = config.id.uuidString
            let provider = SynologyAudioStationProvider(config: config)
            provider.onSessionExpired = { [weak sessionManager] in sessionManager?.clearCredentials() }

            if clearFirst {
                try await songRepository.clear(nasId: nasId)
                try await albumRepository.clear(nasId: nasId)
                try await artistRepository.clear(nasId: nasId)
                try await playlistRepository.clear(nasId: nasId)
            }

            let syncStartedAt = Date()
            let pageSize = 200
            var offset = 0
            var totalSynced = 0
            var total: Int?
            var completedAllPages = false

            while !Task.isCancelled {
                Self.logger.debug("sync batch nas=\(String(nasId.prefix(8)), privacy: .public) offset=\(offset, privacy: .public)")
                let songs = try await provider.fetchSongs(offset: offset, limit: pageSize)
                if offset == 0, songs.isEmpty {
                    total = 0
                }
                try Task.checkCancellation()
                try await songRepository.upsert(songs: songs, nasId: nasId, syncTime: syncStartedAt)
                AppLogger.logAudioStationPathProbe(total: songs.count, pathCount: songs.filter { $0.path?.isEmpty == false }.count)
                await metadataWritebackService?.syncLibraryIndex(songs: songs)
                totalSynced += songs.count
                offset += songs.count
                if songs.count < pageSize {
                    completedAllPages = true
                    total = total ?? totalSynced
                    break
                }
                total = total ?? nil
                status = .syncing(current: totalSynced, total: total, progress: total.map { $0 > 0 ? Double(totalSynced) / Double($0) : nil } ?? nil)
            }

            guard completedAllPages, !Task.isCancelled else {
                status = .cancelled
                throw MusicLibrarySyncError.cancelled
            }

            status = .rebuildingAlbums
            try await albumRepository.rebuildFromSongs(nasId: nasId, syncTime: syncStartedAt)
            status = .rebuildingArtists
            try await artistRepository.rebuildFromSongs(nasId: nasId, syncTime: syncStartedAt)
            try await syncPlaylists(provider: provider, nasId: nasId, syncTime: syncStartedAt)
            try await songRepository.markMissingAsDeleted(nasId: nasId, lastSeenBefore: syncStartedAt)

            let songCount = try await songRepository.count(nasId: nasId)
            let albumCount = try await albumRepository.count(nasId: nasId)
            let artistCount = try await artistRepository.count(nasId: nasId)
            let playlistCount = try await playlistRepository.count(nasId: nasId)
            try await syncStateRepository.upsert(SyncStateRecord(
                nasId: nasId,
                status: "completed",
                lastFullSyncAt: syncStartedAt,
                lastSuccessfulSyncAt: Date(),
                lastFailedSyncAt: nil,
                lastErrorMessage: nil,
                syncedSongCount: songCount,
                totalSongCount: total,
                albumCount: albumCount,
                artistCount: artistCount,
                playlistCount: playlistCount,
                currentOffset: 0
            ))
            status = .completed(date: Date(), songCount: songCount, albumCount: albumCount, artistCount: artistCount)
            await refreshLocalStats()
        } catch is CancellationError {
            status = .cancelled
            await refreshLocalStats()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? MusicLibrarySyncError.unknown.localizedDescription
            if let nasId = sessionManager.config?.id.uuidString {
                try? await syncStateRepository.upsert(SyncStateRecord(
                    nasId: nasId,
                    status: "failed",
                    lastFullSyncAt: nil,
                    lastSuccessfulSyncAt: nil,
                    lastFailedSyncAt: Date(),
                    lastErrorMessage: message,
                    syncedSongCount: 0,
                    totalSongCount: nil,
                    albumCount: 0,
                    artistCount: 0,
                    playlistCount: 0,
                    currentOffset: 0
                ))
            }
            status = .failed(message: message)
            await refreshLocalStats()
        }
    }

    private func syncPlaylists(provider: MusicLibraryProvider, nasId: String, syncTime: Date) async throws {
        let playlists = (try? await provider.fetchPlaylists(offset: 0, limit: 500)) ?? []
        try await playlistRepository.upsert(playlists: playlists, nasId: nasId, syncTime: syncTime)
    }
}
