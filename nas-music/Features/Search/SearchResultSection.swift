//
//  SearchResultSection.swift
//  nas-music
//

import Foundation

enum SearchResultSection: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "歌手"

    var id: String { rawValue }
}

