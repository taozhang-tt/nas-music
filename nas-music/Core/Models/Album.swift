//
//  Album.swift
//  nas-music
//
//  专辑元数据。不再内嵌歌曲列表——AlbumDetailViewModel 通过 MusicLibraryProvider
//  按 album/artistName 匹配筛选歌曲，避免协议层为 Mock/Synology 两套数据源各设计一套
//  「按专辑查歌」的取数方式。
//

import Foundation

struct Album: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let title: String
    let artistName: String
    let year: Int?
    let trackCount: Int?
    let coverId: String?
    let source: MusicSource

    init(
        id: String,
        title: String,
        artistName: String,
        year: Int? = nil,
        trackCount: Int? = nil,
        coverId: String? = nil,
        source: MusicSource
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.year = year
        self.trackCount = trackCount
        self.coverId = coverId
        self.source = source
    }
}
