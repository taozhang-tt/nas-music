//
//  Artist.swift
//  nas-music
//

import Foundation

struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int
}
