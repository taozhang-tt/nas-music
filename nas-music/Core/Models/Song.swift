//
//  Song.swift
//  nas-music
//
//  统一的歌曲模型，Mock / Synology Audio Station 数据源共用。不长期持有播放 URL——
//  Audio Station 的歌曲只保存 source 里的媒体 id，播放前通过
//  MusicLibraryProvider.fetchStreamURL(for:) 动态换取 stream URL。
//

import Foundation

struct Song: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let fileExtension: String?
    let bitrate: Int?
    let sampleRate: Int?
    let fileSize: Int64?
    let coverId: String?
    let path: String?
    let source: MusicSource

    init(
        id: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        duration: TimeInterval? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        fileExtension: String? = nil,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        fileSize: Int64? = nil,
        coverId: String? = nil,
        path: String? = nil,
        source: MusicSource
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.fileExtension = fileExtension
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.fileSize = fileSize
        self.coverId = coverId
        self.path = path
        self.source = source
    }
}

extension Song {
    /// 仅当 source 是 .synology 时有值，用于 SynologyAudioStationProvider 请求歌曲详情/stream URL。
    var audioStationId: String? {
        if case .synology(let audioStationId) = source {
            return audioStationId
        }
        return nil
    }
}
