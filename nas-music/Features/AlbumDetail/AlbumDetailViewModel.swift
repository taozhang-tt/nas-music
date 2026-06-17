//
//  AlbumDetailViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    let album: Album
    private let playbackManager: PlaybackManager

    init(album: Album, playbackManager: PlaybackManager) {
        self.album = album
        self.playbackManager = playbackManager
    }

    var formattedDuration: String { album.totalDuration.formattedAsMinutesSeconds }

    func playAll() {
        playbackManager.play(songs: album.songs, startAt: 0)
    }

    func playSong(at index: Int) {
        playbackManager.play(songs: album.songs, startAt: index)
    }
}
