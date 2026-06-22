//
//  MusicLibraryProvider.swift
//  nas-music
//
//  音乐数据源抽象：MockMusicLibraryProvider 用于无 NAS 连接时开发/预览，
//  SynologyAudioStationProvider 接入真实 Audio Station。上层 ViewModel 只依赖这个协议，
//  替换数据源不需要改动 UI 层。
//

import Foundation

struct PlaybackStreamResource {
    let url: URL
    let headers: [String: String]

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

protocol MusicLibraryProvider {
    func fetchSongs(offset: Int, limit: Int) async throws -> [Song]
    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album]
    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist]
    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist]
    func search(keyword: String) async throws -> MusicSearchResult
    func fetchStreamURL(for song: Song) async throws -> URL
    func fetchStreamResource(for song: Song) async throws -> PlaybackStreamResource
}

extension MusicLibraryProvider {
    static var defaultPageSize: Int { 100 }

    func fetchStreamResource(for song: Song) async throws -> PlaybackStreamResource {
        PlaybackStreamResource(url: try await fetchStreamURL(for: song))
    }

    func search(keyword: String) async throws -> MusicSearchResult {
        let normalized = SearchTextNormalizer.normalize(keyword)
        guard !normalized.isEmpty else {
            return MusicSearchResult(songs: [], albums: [], artists: [])
        }

        async let songs = fetchSongs(offset: 0, limit: 500)
        async let albums = fetchAlbums(offset: 0, limit: 200)
        async let artists = fetchArtists(offset: 0, limit: 200)
        let loaded = try await (songs, albums, artists)

        return MusicSearchResult(
            songs: loaded.0.filter {
                SearchTextNormalizer.normalize($0.title).contains(normalized) ||
                SearchTextNormalizer.normalize($0.artist ?? "").contains(normalized) ||
                SearchTextNormalizer.normalize($0.album ?? "").contains(normalized)
            }.prefix(20).map { $0 },
            albums: loaded.1.filter {
                SearchTextNormalizer.normalize($0.title).contains(normalized) ||
                SearchTextNormalizer.normalize($0.artistName).contains(normalized)
            }.prefix(20).map { $0 },
            artists: loaded.2.filter {
                SearchTextNormalizer.normalize($0.name).contains(normalized)
            }.prefix(20).map { $0 }
        )
    }
}
