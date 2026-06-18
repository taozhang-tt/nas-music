//
//  MusicSource.swift
//  nas-music
//
//  标记一首歌曲来自哪个数据源，决定 PlaybackManager 用模拟引擎还是真实 AVPlayer 播放。
//

import Foundation

enum MusicSource: Codable, Equatable, Hashable {
    case mock(url: String)
    case synology(audioStationId: String)
    case local(fileURL: String)
}
