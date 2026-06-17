//
//  Playlist.swift
//  nas-music
//

import Foundation

struct Playlist: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let songCount: Int
}
