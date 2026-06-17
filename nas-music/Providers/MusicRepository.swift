//
//  MusicRepository.swift
//  nas-music
//
//  音乐库数据的抽象协议。当前由 MockMusicRepository 实现；
//  未来可替换为真实的 AudioStation / WebDAV Repository 而不影响上层 ViewModel。
//

import Foundation

protocol MusicRepository {
    func fetchRecentlyPlayed() async -> [Song]
    func fetchRecentlyAdded() async -> [Song]
    func fetchAllSongs() async -> [Song]
    func fetchAllAlbums() async -> [Album]
    func fetchAllArtists() async -> [Artist]
}
