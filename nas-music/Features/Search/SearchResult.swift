//
//  SearchResult.swift
//  nas-music
//

import Foundation

enum SearchViewState: Equatable {
    case idle
    case searching
    case loaded(MusicSearchResult)
    case empty
    case failed(message: String)

    static func == (lhs: SearchViewState, rhs: SearchViewState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.searching, .searching), (.empty, .empty):
            return true
        case (.failed(let lhsMessage), .failed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.loaded(let lhsResult), .loaded(let rhsResult)):
            return lhsResult.songs == rhsResult.songs &&
            lhsResult.albums == rhsResult.albums &&
            lhsResult.artists == rhsResult.artists
        default:
            return false
        }
    }
}

