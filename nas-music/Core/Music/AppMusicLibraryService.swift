//
//  AppMusicLibraryService.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class AppMusicLibraryService: ObservableObject {
    private let sessionManager: NASSessionManager
    private let remoteProvider: MusicLibraryProvider
    private let songRepository: SongRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let artistRepository: ArtistRepositoryProtocol
    private let playlistRepository: PlaylistRepositoryProtocol
    private let syncStateRepository: SyncStateRepositoryProtocol
    private let mockProvider: MockMusicLibraryProvider

    init(
        sessionManager: NASSessionManager,
        remoteProvider: MusicLibraryProvider,
        songRepository: SongRepositoryProtocol = SongRepository(),
        albumRepository: AlbumRepositoryProtocol = AlbumRepository(),
        artistRepository: ArtistRepositoryProtocol = ArtistRepository(),
        playlistRepository: PlaylistRepositoryProtocol = PlaylistRepository(),
        syncStateRepository: SyncStateRepositoryProtocol = SyncStateRepository(),
        mockProvider: MockMusicLibraryProvider = MockMusicLibraryProvider()
    ) {
        self.sessionManager = sessionManager
        self.remoteProvider = remoteProvider
        self.songRepository = songRepository
        self.albumRepository = albumRepository
        self.artistRepository = artistRepository
        self.playlistRepository = playlistRepository
        self.syncStateRepository = syncStateRepository
        self.mockProvider = mockProvider
    }

    private var nasId: String? { sessionManager.config?.id.uuidString }

    func loadSongs(offset: Int, limit: Int) async throws -> [Song] {
        guard let nasId else { return try await mockProvider.fetchSongs(offset: offset, limit: limit) }
        let count = try await songRepository.count(nasId: nasId)
        guard count > 0 else { return [] }
        return try await songRepository.fetchSongs(nasId: nasId, offset: offset, limit: limit)
    }

    func loadAlbums(offset: Int, limit: Int) async throws -> [Album] {
        guard let nasId else { return try await mockProvider.fetchAlbums(offset: offset, limit: limit) }
        return try await albumRepository.fetchAlbums(nasId: nasId, offset: offset, limit: limit)
    }

    func loadArtists(offset: Int, limit: Int) async throws -> [Artist] {
        guard let nasId else { return try await mockProvider.fetchArtists(offset: offset, limit: limit) }
        return try await artistRepository.fetchArtists(nasId: nasId, offset: offset, limit: limit)
    }

    func loadPlaylists(offset: Int, limit: Int) async throws -> [Playlist] {
        guard let nasId else { return try await mockProvider.fetchPlaylists(offset: offset, limit: limit) }
        return try await playlistRepository.fetchPlaylists(nasId: nasId, offset: offset, limit: limit)
    }

    func search(keyword: String) async throws -> MusicSearchResult {
        guard let nasId, !SearchTextNormalizer.normalize(keyword).isEmpty else {
            return MusicSearchResult(songs: [], albums: [], artists: [])
        }
        async let songs = songRepository.search(nasId: nasId, keyword: keyword, offset: 0, limit: 20)
        async let albums = albumRepository.search(nasId: nasId, keyword: keyword, offset: 0, limit: 20)
        async let artists = artistRepository.search(nasId: nasId, keyword: keyword, offset: 0, limit: 20)
        return try await MusicSearchResult(songs: songs, albums: albums, artists: artists)
    }

    func resolveStreamURL(for song: Song) async throws -> URL {
        guard sessionManager.state == .connected else { throw MusicLibrarySyncError.nasNotConnected }
        return try await remoteProvider.fetchStreamURL(for: song)
    }

    func resolveStreamResource(for song: Song) async throws -> PlaybackStreamResource {
        guard sessionManager.state == .connected else { throw MusicLibrarySyncError.nasNotConnected }
        return try await remoteProvider.fetchStreamResource(for: song)
    }
}

final class AppMusicLibraryProvider: MusicLibraryProvider {
    private let service: AppMusicLibraryService

    init(service: AppMusicLibraryService) {
        self.service = service
    }

    func fetchSongs(offset: Int, limit: Int) async throws -> [Song] {
        try await service.loadSongs(offset: offset, limit: limit)
    }

    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album] {
        try await service.loadAlbums(offset: offset, limit: limit)
    }

    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist] {
        try await service.loadArtists(offset: offset, limit: limit)
    }

    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist] {
        try await service.loadPlaylists(offset: offset, limit: limit)
    }

    func search(keyword: String) async throws -> MusicSearchResult {
        try await service.search(keyword: keyword)
    }

    func fetchStreamURL(for song: Song) async throws -> URL {
        try await service.resolveStreamURL(for: song)
    }

    func fetchStreamResource(for song: Song) async throws -> PlaybackStreamResource {
        try await service.resolveStreamResource(for: song)
    }
}
