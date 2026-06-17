//
//  Song.swift
//  nas-music
//

import Foundation

struct Song: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let coverURL: String?
    let streamURL: URL?
}
