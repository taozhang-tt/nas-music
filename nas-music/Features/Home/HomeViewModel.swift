//
//  HomeViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [Song] = []
    @Published private(set) var recentlyAdded: [Song] = []
    @Published private(set) var songCount = 0
    @Published private(set) var albumCount = 0
    @Published private(set) var artistCount = 0
    @Published var searchText = ""
    @Published private(set) var searchResults: [Song] = []

    private let musicLibrary: MusicLibraryProviding
    private let playbackManager: PlaybackManager
    private var allSongs: [Song] = []

    init(musicLibrary: MusicLibraryProviding, playbackManager: PlaybackManager) {
        self.musicLibrary = musicLibrary
        self.playbackManager = playbackManager
    }

    func load() async {
        async let recent = musicLibrary.fetchRecentlyPlayed()
        async let added = musicLibrary.fetchRecentlyAdded()
        async let songs = musicLibrary.fetchAllSongs()
        async let albums = musicLibrary.fetchAllAlbums()
        async let artists = musicLibrary.fetchAllArtists()

        recentlyPlayed = await recent
        recentlyAdded = await added
        allSongs = await songs
        albumCount = await albums.count
        artistCount = await artists.count
        songCount = allSongs.count
    }

    func updateSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        let keyword = searchText.lowercased()
        searchResults = allSongs.filter {
            $0.title.lowercased().contains(keyword) || $0.artistName.lowercased().contains(keyword)
        }
    }

    func playRecentlyPlayed(at index: Int) {
        playbackManager.play(songs: recentlyPlayed, startAt: index)
    }

    func playRecentlyAdded(at index: Int) {
        playbackManager.play(songs: recentlyAdded, startAt: index)
    }

    func playSearchResult(at index: Int) {
        playbackManager.play(songs: searchResults, startAt: index)
    }
}
