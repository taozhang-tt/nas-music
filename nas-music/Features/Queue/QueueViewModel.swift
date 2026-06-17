//
//  QueueViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class QueueViewModel: ObservableObject {
    private let playbackManager: PlaybackManager
    private var cancellable: AnyCancellable?

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        cancellable = playbackManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var queue: [Song] { playbackManager.queue }
    var currentIndex: Int { playbackManager.currentIndex }

    func isCurrent(_ index: Int) -> Bool { index == currentIndex }

    func selectSong(at index: Int) {
        playbackManager.playSong(at: index)
    }

    func removeSong(at index: Int) {
        playbackManager.removeFromQueue(at: index)
    }
}
