//
//  Song.swift
//  nas-music
//

import Foundation

struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String
    let duration: TimeInterval
    let trackNumber: Int
}
