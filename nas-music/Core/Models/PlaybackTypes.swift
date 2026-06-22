//
//  PlaybackTypes.swift
//  nas-music
//

import Foundation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case failed(message: String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

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
