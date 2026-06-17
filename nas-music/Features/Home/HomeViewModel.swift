//
//  HomeViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var allSongsPreview: [Song] = []
    @Published private(set) var recentlyAdded: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var songCount = 0
    @Published private(set) var albumCount = 0
    @Published private(set) var artistCount = 0
    @Published var searchText = ""
    @Published private(set) var searchResults: [Song] = []
    @Published private(set) var state: MusicLibraryViewState = .idle

    let providerStore: MusicLibraryProviderStore
    private var provider: MusicLibraryProvider { providerStore.activeProvider }
    private let previewPageSize = 200
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

    var nasConnectionState: NASConnectionState { providerStore.connectionState }
    var nasDisplayName: String? { providerStore.nasDisplayName }
    var nasLastConnectedAt: Date? { providerStore.lastConnectedAt }
    var isUsingSynology: Bool { providerStore.isUsingSynology }

    func load() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        do {
            async let songsResult = provider.fetchSongs(offset: 0, limit: previewPageSize)
            async let albumsResult = provider.fetchAlbums(offset: 0, limit: previewPageSize)
            async let artistsResult = provider.fetchArtists(offset: 0, limit: previewPageSize)
            let (loadedSongs, loadedAlbums, loadedArtists) = try await (songsResult, albumsResult, artistsResult)

            allSongsPreview = loadedSongs
            recentlyAdded = Array(loadedSongs.prefix(20))
            songCount = loadedSongs.count
            albumCount = loadedAlbums.count
            artistCount = loadedArtists.count
            playlists = (try? await provider.fetchPlaylists(offset: 0, limit: 50)) ?? []

            updateSearchResults()
            state = loadedSongs.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription ?? "加载失败，请重试。")
        }
    }

    func updateSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        let keyword = searchText.lowercased()
        searchResults = allSongsPreview.filter {
            $0.title.lowercased().contains(keyword) || ($0.artist?.lowercased().contains(keyword) ?? false)
        }
    }
}
