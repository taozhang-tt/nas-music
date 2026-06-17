//
//  PlaybackTypes.swift
//  nas-music
//

import Foundation

enum RepeatMode {
    case off
    case all
    case one

    mutating func cycle() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }

    var iconName: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var isActive: Bool { self != .off }
}
