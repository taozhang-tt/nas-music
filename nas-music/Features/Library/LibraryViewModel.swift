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

    var id: String { rawValue }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var selectedSegment: LibrarySegment = .songs
    @Published var searchText = ""
    @Published private(set) var songs: [Song] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [Artist] = []

    private let musicRepository: MusicRepository

    init(musicRepository: MusicRepository) {
        self.musicRepository = musicRepository
    }

    func load() async {
        async let songsResult = musicRepository.fetchAllSongs()
        async let albumsResult = musicRepository.fetchAllAlbums()
        async let artistsResult = musicRepository.fetchAllArtists()
        songs = await songsResult
        albums = await albumsResult
        artists = await artistsResult
    }

    var filteredSongs: [Song] {
        filter(songs) { $0.title.lowercased().contains($1) || $0.artist.lowercased().contains($1) }
    }

    var filteredAlbums: [Album] {
        filter(albums) { $0.title.lowercased().contains($1) || $0.artistName.lowercased().contains($1) }
    }

    var filteredArtists: [Artist] {
        filter(artists) { $0.name.lowercased().contains($1) }
    }

    private func filter<T>(_ items: [T], _ matches: (T, String) -> Bool) -> [T] {
        guard !searchText.isEmpty else { return items }
        let keyword = searchText.lowercased()
        return items.filter { matches($0, keyword) }
    }
}
