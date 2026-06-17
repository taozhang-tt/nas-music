//
//  MusicLibraryProviding.swift
//  nas-music
//
//  音乐库数据的抽象协议。当前由 MockMusicLibraryProvider 实现；
//  未来可替换为真实的 AudioStation / WebDAV Provider 而不影响上层 ViewModel。
//

import Foundation

protocol MusicLibraryProviding {
    func fetchRecentlyPlayed() async -> [Song]
    func fetchRecentlyAdded() async -> [Song]
    func fetchAllSongs() async -> [Song]
    func fetchAllAlbums() async -> [Album]
    func fetchAllArtists() async -> [Artist]
}
