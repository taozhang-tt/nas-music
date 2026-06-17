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

    private let musicRepository: MusicRepository
    private var allSongs: [Song] = []

    init(musicRepository: MusicRepository) {
        self.musicRepository = musicRepository
    }

    func load() async {
        async let recent = musicRepository.fetchRecentlyPlayed()
        async let added = musicRepository.fetchRecentlyAdded()
        async let songs = musicRepository.fetchAllSongs()
        async let albums = musicRepository.fetchAllAlbums()
        async let artists = musicRepository.fetchAllArtists()

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
            $0.title.lowercased().contains(keyword) || $0.artist.lowercased().contains(keyword)
        }
    }
}
