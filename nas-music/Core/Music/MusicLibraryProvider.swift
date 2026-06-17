//
//  MusicLibraryProvider.swift
//  nas-music
//
//  音乐数据源抽象：MockMusicLibraryProvider 用于无 NAS 连接时开发/预览，
//  SynologyAudioStationProvider 接入真实 Audio Station。上层 ViewModel 只依赖这个协议，
//  替换数据源不需要改动 UI 层。
//

import Foundation

protocol MusicLibraryProvider {
    func fetchSongs(offset: Int, limit: Int) async throws -> [Song]
    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album]
    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist]
    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist]
    func fetchStreamURL(for song: Song) async throws -> URL
}

extension MusicLibraryProvider {
    static var defaultPageSize: Int { 100 }
}
