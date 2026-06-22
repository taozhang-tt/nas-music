//
//  LibraryViewModel.swift
//  nas-music
//

import Foundation
import Combine

enum LibrarySegment: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "歌手"
    case playlists = "播放列表"

    var id: String { rawValue }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var selectedSegment: LibrarySegment = .songs
    @Published var searchText = ""
    @Published private(set) var songs: [Song] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var state: MusicLibraryViewState = .idle

    private let providerStore: MusicLibraryProviderStore
    private var provider: MusicLibraryProvider { providerStore.activeProvider }
    var activeProvider: MusicLibraryProvider { providerStore.activeProvider }
    private let songPageSize = 100
    private let metadataPageSize = 50

    private var songsOffset = 0
    private var albumsOffset = 0
    private var artistsOffset = 0
    private var playlistsOffset = 0
    private var songsExhausted = false
    private var albumsExhausted = false
    private var artistsExhausted = false
    private var playlistsExhausted = false
    private var isLoadingMoreSongs = false
    private var isLoadingMoreAlbums = false
    private var isLoadingMoreArtists = false
    private var isLoadingMorePlaylists = false
    private var providerCancellable: AnyCancellable?

    init(providerStore: MusicLibraryProviderStore) {
        self.providerStore = providerStore
        // NAS 连接状态变化时 activeProvider 会切换（Mock <-> Synology），这里跟着重新加载，
        // 否则已经显示过的页面会一直停留在切换前的数据上，直到用户手动下拉刷新。
        providerCancellable = providerStore.$activeProvider
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    func load() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        songsOffset = 0
        albumsOffset = 0
        artistsOffset = 0
        playlistsOffset = 0
        songsExhausted = false
        albumsExhausted = false
        artistsExhausted = false
        playlistsExhausted = false

        do {
            async let songsResult = provider.fetchSongs(offset: 0, limit: songPageSize)
            async let albumsResult = provider.fetchAlbums(offset: 0, limit: metadataPageSize)
            async let artistsResult = provider.fetchArtists(offset: 0, limit: metadataPageSize)
            async let playlistsResult = provider.fetchPlaylists(offset: 0, limit: metadataPageSize)
            let (loadedSongs, loadedAlbums, loadedArtists, loadedPlaylists) = try await (songsResult, albumsResult, artistsResult, playlistsResult)

            songs = loadedSongs
            albums = loadedAlbums
            artists = loadedArtists
            playlists = loadedPlaylists
            songsOffset = loadedSongs.count
            albumsOffset = loadedAlbums.count
            artistsOffset = loadedArtists.count
            playlistsOffset = loadedPlaylists.count
            songsExhausted = loadedSongs.count < songPageSize
            albumsExhausted = loadedAlbums.count < metadataPageSize
            artistsExhausted = loadedArtists.count < metadataPageSize
            playlistsExhausted = loadedPlaylists.count < metadataPageSize

            state = (loadedSongs.isEmpty && loadedAlbums.isEmpty && loadedArtists.isEmpty && loadedPlaylists.isEmpty) ? .empty : .loaded
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    func syncAndRefresh(using syncService: MusicLibrarySyncService) async {
        await syncService.syncLibrary()
        await refresh()
    }

    func loadMoreSongsIfNeeded(currentItem song: Song) {
        guard searchText.isEmpty, !songsExhausted, !isLoadingMoreSongs else { return }
        guard let index = songs.firstIndex(where: { $0.id == song.id }), index >= songs.count - 5 else { return }
        Task { await loadMoreSongs() }
    }

    func loadMoreAlbumsIfNeeded(currentItem album: Album) {
        guard searchText.isEmpty, !albumsExhausted, !isLoadingMoreAlbums else { return }
        guard let index = albums.firstIndex(where: { $0.id == album.id }), index >= albums.count - 5 else { return }
        Task { await loadMoreAlbums() }
    }

    func loadMoreArtistsIfNeeded(currentItem artist: Artist) {
        guard searchText.isEmpty, !artistsExhausted, !isLoadingMoreArtists else { return }
        guard let index = artists.firstIndex(where: { $0.id == artist.id }), index >= artists.count - 5 else { return }
        Task { await loadMoreArtists() }
    }

    func loadMorePlaylistsIfNeeded(currentItem playlist: Playlist) {
        guard searchText.isEmpty, !playlistsExhausted, !isLoadingMorePlaylists else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }), index >= playlists.count - 5 else { return }
        Task { await loadMorePlaylists() }
    }

    private func loadMoreSongs() async {
        guard !isLoadingMoreSongs, !songsExhausted else { return }
        isLoadingMoreSongs = true
        defer { isLoadingMoreSongs = false }
        do {
            let next = try await provider.fetchSongs(offset: songsOffset, limit: songPageSize)
            songsOffset += next.count
            if next.count < songPageSize { songsExhausted = true }
            songs.append(contentsOf: next)
        } catch {
            songsExhausted = true
        }
    }

    private func loadMoreAlbums() async {
        guard !isLoadingMoreAlbums, !albumsExhausted else { return }
        isLoadingMoreAlbums = true
        defer { isLoadingMoreAlbums = false }
        do {
            let next = try await provider.fetchAlbums(offset: albumsOffset, limit: metadataPageSize)
            albumsOffset += next.count
            if next.count < metadataPageSize { albumsExhausted = true }
            albums.append(contentsOf: next)
        } catch {
            albumsExhausted = true
        }
    }

    private func loadMoreArtists() async {
        guard !isLoadingMoreArtists, !artistsExhausted else { return }
        isLoadingMoreArtists = true
        defer { isLoadingMoreArtists = false }
        do {
            let next = try await provider.fetchArtists(offset: artistsOffset, limit: metadataPageSize)
            artistsOffset += next.count
            if next.count < metadataPageSize { artistsExhausted = true }
            artists.append(contentsOf: next)
        } catch {
            artistsExhausted = true
        }
    }

    private func loadMorePlaylists() async {
        guard !isLoadingMorePlaylists, !playlistsExhausted else { return }
        isLoadingMorePlaylists = true
        defer { isLoadingMorePlaylists = false }
        do {
            let next = try await provider.fetchPlaylists(offset: playlistsOffset, limit: metadataPageSize)
            playlistsOffset += next.count
            if next.count < metadataPageSize { playlistsExhausted = true }
            playlists.append(contentsOf: next)
        } catch {
            playlistsExhausted = true
        }
    }

    var filteredSongs: [Song] {
        filter(songs) { $0.title.lowercased().contains($1) || ($0.artist?.lowercased().contains($1) ?? false) }
    }

    var filteredAlbums: [Album] {
        filter(albums) { $0.title.lowercased().contains($1) || $0.artistName.lowercased().contains($1) }
    }

    var filteredArtists: [Artist] {
        filter(artists) { $0.name.lowercased().contains($1) }
    }

    var filteredPlaylists: [Playlist] {
        filter(playlists) { $0.name.lowercased().contains($1) }
    }

    private func filter<T>(_ items: [T], _ matches: (T, String) -> Bool) -> [T] {
        guard !searchText.isEmpty else { return items }
        let keyword = searchText.lowercased()
        return items.filter { matches($0, keyword) }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "加载失败，请重试。"
    }
}
