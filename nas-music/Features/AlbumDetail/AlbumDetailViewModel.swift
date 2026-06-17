//
//  AlbumDetailViewModel.swift
//  nas-music
//
//  Album 不再内嵌歌曲列表，这里通过 MusicLibraryProvider 拉一页歌曲后按专辑名/专辑歌手
//  过滤出属于这张专辑的曲目。
//

import Foundation
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    let album: Album
    @Published private(set) var songs: [Song] = []
    @Published private(set) var state: MusicLibraryViewState = .idle

    private let provider: MusicLibraryProvider
    private let pageSize = 500
    private let maxPagesScanned = 6

    init(album: Album, provider: MusicLibraryProvider) {
        self.album = album
        self.provider = provider
    }

    var formattedDuration: String {
        songs.reduce(0) { $0 + ($1.duration ?? 0) }.formattedAsMinutesSeconds
    }

    var subtitle: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        let trackCount = album.trackCount ?? (songs.isEmpty ? nil : songs.count)
        if let trackCount { parts.append("\(trackCount) 首歌曲") }
        if !songs.isEmpty { parts.append(formattedDuration) }
        return parts.joined(separator: " · ")
    }

    func load() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        do {
            var matched: [Song] = []
            var offset = 0
            for _ in 0..<maxPagesScanned {
                let page = try await provider.fetchSongs(offset: offset, limit: pageSize)
                matched.append(contentsOf: page.filter { song -> Bool in
                    guard song.album == album.title else { return false }
                    let songAlbumArtist = song.albumArtist ?? song.artist
                    return songAlbumArtist == album.artistName
                })
                offset += page.count
                if page.count < pageSize { break }
            }
            songs = matched.sorted { (lhs: Song, rhs: Song) -> Bool in
                (lhs.trackNumber ?? Int.max) < (rhs.trackNumber ?? Int.max)
            }
            state = songs.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(message: (error as? LocalizedError)?.errorDescription ?? "加载失败，请重试。")
        }
    }
}
