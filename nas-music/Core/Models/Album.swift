//
//  Album.swift
//  nas-music
//

import Foundation

struct Album: Identifiable {
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

extension Album: Equatable {
    static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }
}

extension Album: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
