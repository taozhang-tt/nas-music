//
//  Album.swift
//  nas-music
//

import Foundation

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let year: Int
    let songs: [Song]

    var trackCount: Int { songs.count }

    var totalDuration: TimeInterval {
        songs.reduce(0) { $0 + $1.duration }
    }
}
