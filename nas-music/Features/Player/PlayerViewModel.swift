//
//  PlayerViewModel.swift
//  nas-music
//
//  转发 PlaybackManager 的变化通知，并暴露播放页所需的展示态（格式化时间、进度等）。
//

import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    private let playbackManager: PlaybackManager
    private var cancellable: AnyCancellable?

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        cancellable = playbackManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var song: Song? { playbackManager.currentSong }
    var isPlaying: Bool { playbackManager.isPlaying }
    var progress: Double { playbackManager.progress }
    var currentTimeText: String { playbackManager.currentTime.formattedAsMinutesSeconds }
    var durationText: String { playbackManager.duration.formattedAsMinutesSeconds }
    var isShuffled: Bool { playbackManager.isShuffled }
    var repeatMode: RepeatMode { playbackManager.repeatMode }
    var queueCount: Int { playbackManager.queue.count }

    func playPause() { playbackManager.playPause() }
    func skipToNext() { playbackManager.skipToNext() }
    func skipToPrevious() { playbackManager.skipToPrevious() }
    func toggleShuffle() { playbackManager.toggleShuffle() }
    func cycleRepeatMode() { playbackManager.repeatMode.cycle() }

    func seek(toFraction fraction: Double) {
        playbackManager.seek(to: playbackManager.duration * fraction)
    }

    func makeQueueViewModel() -> QueueViewModel {
        QueueViewModel(playbackManager: playbackManager)
    }
}
